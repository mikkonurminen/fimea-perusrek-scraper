#!/bin/bash

set -e

current_date=$(date +%y-%m-%d)
curl=$(which curl)
iconv=$(which iconv)

echo "-------------------------------" >> run.log
mkdir -p ./temp

# Tee backupit edellisestä ajosta
mkdir -p ./backup/data ./backup/edellinen_ajo/

if [ -f ./run.log ]; then
    cp ./run.log ./backup/edellinen_ajo/run.log
fi
if [ -d ./edellinen_ajo ] && [ -f ./edellinen_ajo/saate.txt ]; then
    echo "$current_date Tehdään backupit ./backup/edellinen_ajo" >> run.log
    cp -r ./edellinen_ajo/* ./backup/edellinen_ajo/
fi
if [ -d ./data ] && [ -f ./data/tehdyt_ajot.txt ]; then
    echo "$current_date Tehdään backupit ./backup/data" >> run.log
    cp -r ./data/* ./backup/data/
fi

echo "$current_date curl fimea.fi..." >> run.log
#curl -Sso ./temp/fimea.html https://fimea.fi/laakehaut_ja_luettelot/perusrekisteri 2>>run.log

function extract_link() {
    echo "$current_date Haetaan linkki $1..." >> run.log
    local link=$(cat ./temp/fimea.html | grep -w "${1}.txt" | sed -e 's/.*href=\"\(.*\)\">.*/\1/')
    echo "https://fimea.fi${link}"
}

function dl_file() {
    echo "$current_date Ladataan $1..." >> run.log
    local link=$(extract_link ${1})
    echo "$current_date curl $link" >> run.log
    curl -Sso ./temp/$1.txt $link 2>>run.log
    if [ $? -ne 0 ]; then
        echo "Url virhe latauksessa $file.txt" >> run.log
        echo 1 && return 1
    fi

    # Tarkista, että curl ladannut tiedoston, eikä html-sivua
    local file=./temp/$1.txt
    wc_file=$(cat "$file" | wc -l)
    wc_file_html=$(cat "$file" | grep "DOCTYPE html" | wc -l)
    if [ $wc_file_html -gt 0 ] || [ $wc_file -eq 0 ] || [ ! -f $file ]; then
        echo 1 && return 1
    fi

    # Tarkista saatteen kohdalla vielä, että on vain yksi rivi
    if [ "$1" == "saate" ] && [ $wc_file -gt 1 ]; then
        echo -e "$current_date Exit 1. Virhe $file. Tarkista rivien määrä ja curl." >> run.log
        echo 1 && return 1
    fi
    echo $file
}

function encoding_to_utf8() {
    # Tarkista ja muuta utf-8, koska Fimea tallentaa iso-8859-1
    local encoding=$(file -bi "$1" | awk '/charset/ { print $2 }' | cut -d'=' -f 2)
    if [ "$encoding" != "utf-8" ]; then
        echo "$current_date $1 encoding utf-8..." >> run.log
        iconv -f "$encoding" -t "utf-8" $1 -o "$1-temp"
        mv -f "$1-temp" "$1"
        echo "$current_date $1 encoding utf-8 valmis." >> run.log
    fi
}

function compare_line_count() {
    local lc_uusi_atc=$(cat ./temp/$1_uusi.txt | wc -l)
    local lc_vanha_atc=$(cat ./data/$1.txt | wc -l)
    if [ $lc_uusi_atc -ge $lc_vanha_atc ]; then
        # cp ./temp/$1_uusi.txt ./data/$1.txt
        echo "$current_date ./data/$1.txt päivitetty." >> run.log
    else
        # TODO Testaa tämä
        echo "$current_date Virhe: päivitetyn $1.txt rivien määrä pienempi kuin edellisen." >> run.log
    fi
}

# Lataa filet
echo "$current_date Ladataan tiedostot Fimeasta..." >> run.log
# file=("saate" "atc" "laakemuoto" "laakeaine" "maaraamisehto" "maaraaikaisetmaaraamisehto" "sailytysastia" "pakkaus_nolla" "pakkaus1" "pakkaus-m")
filet=("saate" "atc")
len=${#filet[@]}
i=$(echo 0)
for file in "${filet[@]}"; do
    eval "uusi_$file=$(dl_file $file)"
    if [ ! -f "$(eval echo \$uusi_${file})" ]; then
        echo -e "$current_date Exit 1. Virhe ladattaessa $file.txt. Tarkista curl." >> run.log
        # rm -rf ./temp
        exit 1
    fi

    encoding_to_utf8 "$(eval echo \$uusi_${file})"

    # Odota latauksien välillä
    [ $i -lt $(($len - 1)) ] && sleep 5
    i=$(($i + 1))
done
unset i len filet

# TODO loop
edellinen_saate=./edellinen_ajo/saate.txt
edellinen_atc=./edellinen_ajo/atc.txt

# Tarkista, onko varmasti ensimmäinen kerta kun tiedostot haetaan
if [ ! -f "$edellinen_saate" ] || [ ! -f ./data/tehdyt_ajot.txt ] || [ ! -f ./data/atc.txt ]; then
    echo "$current_date Edellisen ajon saatetta ei löytynyt. Tallennetaan datat uutena." >> run.log

    encoding_to_utf8 $uusi_saate
    encoding_to_utf8 $uusi_atc

    mkdir -p ./data
    mkdir -p ./edellinen_ajo

    if [ ! -f ./data/tehdyt_ajot.txt ]; then
        cp $uusi_saate ./data/tehdyt_ajot.txt
        cp $uusi_saate ./edellinen_ajo/saate.txt
        echo "$current_date $uusi_saate kopiotu ./data ./edellinen_ajo" >> run.log
    fi

    if [ ! -f ./data/atc.txt ]; then
        cp $uusi_atc ./data/atc.txt
        cp $uusi_atc ./edellinen_ajo/atc.txt
        echo "$current_date $uusi_atc kopiotu ./data ./edellinen_ajo" >> run.log
    fi

    # Tee backupit
    echo "$current_date Tehdään backupit ./backup" >> run.log
    mkdir -p ./backup/temp
    cp -r ./edellinen_ajo/* ./backup/edellinen_ajo/
    cp -r ./data/* ./backup/data/
    cp -r ./temp/* ./backup/temp/

    echo -e "$current_date Datat tallennettu uutena.\n" >> run.log
    exit 0
fi

# Tarkista, onko saate identtinen edellisen kanssa
if [ "$(cmp --silent "$edellinen_saate" "$uusi_saate"; echo $?)" -eq 0 ]; then
    echo -e "$current_date Ei päivitystä edelliseen Fimean ajoon.\n" >> run.log
    exit 0
fi

# Hae ajopvm uudesta saatteesta ja muuta formaatti
ajopvm=$(
    awk '{
      for (i=1; i <= NF; i++)
        if (tolower($i) == "ajopvm:")
          print $(i+1)
    }' "$uusi_saate"
)

if [ ! -n "$ajopvm" ]; then
    echo -e "$current_date Exit 1. Ajopvm ei löytynyt uudesta ajosta. Tarkista saate.txt\n" >> run.log
    exit 1
fi

# Poista mahdollinen whitespace ja tarkista numerot
ajopvm=$(echo $ajopvm | sed '/^$/d;s/[[:blank:]]//g')
kk="$(cut -d'.' -f2 <<<"$ajopvm")"
paiva="$(cut -d'.' -f1 <<<"$ajopvm")"
vuosi="$(cut -d'.' -f3 <<<"$ajopvm")"

if [ "$paiva" -lt 1 ] ||  [ "$paiva" -gt 31 ]; then
    echo "$current_date Virhe: ajopvm paiva-muuttuja < 1 tai > 31. Tarkista saate.txt" >> run.log
    exit 1
fi
if [ "$kk" -lt 1 ] || [ "$kk" -gt 12 ]; then
    echo "$current_date Virhe: ajopvm kuukausi-muuttuja < 1 tai > 12. Tarkista saate.txt." >> run.log
    exit 1
fi
if [ "${#vuosi}" -ne 4 ]; then
    echo "$current_date Virhe: ajopvm vuosi-muuttujassa. Tarkista saate.txt." >> run.log
    exit 1
fi

# Lisää nolla eteen jos luku < 10
[ "${#paiva}" -lt 2 ] && paiva="0$paiva"
[ "${#kk}" -lt 2 ] && kk="0$kk"

ajopvm="$vuosi-$kk-$paiva"

# TODO loop ja funktio? Esim. sort_var="$-k2,2 -k1,1" && sort -t';' $sort_var -o output.txt
# Ota talteen uudet rivit
echo "$current_date Otetaan talteen uudet uniikit rivit atc..." >> run.log
uniq_atc=$(cat "$edellinen_atc" "$uusi_atc" | sort | uniq -u)

lc_atc=$(echo "$uniq_atc" | wc -l)
if [ $lc_atc -gt 0 ]; then
    # TODO lisää ajopvm sarake sekä arvot tiedostoihin
    echo "$uniq_atc" > ./edellinen_ajo/atc_uudet_rivit.txt

    # 1) Ota header pois; 2) yhdistä uniikit rivit; 3) sort; 4) yhdistä header ja sortatut rivit
    echo "$current_date Lisätään uniikit rivit dataan..." >> run.log
    { sed -e 1d ./data/atc.txt; echo "$uniq_atc"; } \
        | sort -t';' -k2 -o ./temp/atc_temp.txt \
        && head -1 ./data/atc.txt \
        | cat - ./temp/atc_temp.txt > ./temp/atc_uusi.txt

    # Tarkista että päivitetyssä tiedostossa vähintään saman verran rivejä kuin vanhassa
    compare_line_count "atc"
else
    echo "$current_date atc.txt uusien uniikkien rivien määrä 0." >> run.log
fi

# Korvaa ./edellinen_ajo uudella ajolla
echo "$current_date Korvataan ./edellinen_ajo uudella ajolla." >> run.log
cp $uusi_saate ./edellinen_ajo/saate.txt
cp $uusi_atc ./edellinen_ajo/atc.txt

# Lisää saate tehtyihin ajoihin TODO pitäisikö siirtää myöhemmäksi
cat "$uusi_saate" >> ./data/tehdyt_ajot.txt

# Backup temp ennen tyhjennystä
cp -r ./temp/* ./backup/temp/

echo "Script ajettu $(date +%y-%m-%d' '%T)" > ./edellinen_ajo/skripti_ajettu_pvm.txt
echo -e "$curent_date Script ajo valmis.\n" >> run.log
