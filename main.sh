#!/bin/bash

set -eu

current_date=$(date +%Y-%m-%d-%T)
wget=$(which wget)
iconv=$(which iconv)

mkdir -p ./temp

# Tee backupit edellisestä ajosta
mkdir -p ./backup/data ./backup/edellinen_ajo/

echo "-------------------------------" >> run.log
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

echo "$current_date wget fimea.fi..." >> run.log
wget -nv -O ./temp/fimea.html \
    --no-cache --no-cookies --header="Accept: text/html" \
    --user-agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:21.0) Gecko/20100101 Firefox/21.0" \
    https://fimea.fi/laakehaut_ja_luettelot/perusrekisteri 2>>run.log

function extract_link() {
    echo "$current_date Haetaan linkki $1..." >> run.log
    local link=$(cat ./temp/fimea.html | grep -w "${1}.txt" | sed -e 's/.*href=\"\(.*\)\">.*/\1/')
    echo "https://fimea.fi${link}"
}

function dl_file() {
    echo "$current_date Ladataan $1..." >> run.log
    local link=$(extract_link ${1})

    echo "$current_date wget $link" >> run.log
    wget -nv -O ./temp/$1.txt \
        --no-cache --no-cookies --header="Accept: text/html" \
        --user-agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:21.0) Gecko/20100101 Firefox/21.0" \
        $link 2>>run.log

    if [ $? -ne 0 ]; then
        echo "Url virhe latauksessa $file.txt" >> run.log
        echo 1 && return 1
    fi

    # Tarkista, että 1) tiedosto ei ole tyhjä 2) wget on ladannut tiedoston eikä html-sivua
    local file=./temp/$1.txt
    wc_file=$(cat "$file" | wc -l)
    wc_file_html=$(cat "$file" | grep "DOCTYPE html" | wc -l)
    if [ $wc_file_html -gt 0 ] || [ $wc_file -eq 0 ] || [ ! -f $file ]; then
        echo -e "$current_date Exit 1. Virhe ladattaessa $file.txt. Tarkista wget." >> run.log
        # rm -rf ./temp
        exit 1
    fi

    # Tarkista saatteen kohdalla vielä, että on vain yksi rivi
    if [ "$1" == "saate" ] && [ $wc_file -gt 1 ]; then
        echo -e "$current_date Exit 1. Virhe $file. Tarkista rivien määrä ja wget." >> run.log
        exit 1
    fi
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

function hae_ajopvm() {
    # Hae ajopvm uudesta saatteesta ja muuta formaatti
    ajopvm=$(
        awk '{
      for (i=1; i <= NF; i++)
        if (tolower($i) == "ajopvm:")
          print $(i+1)
        }' ./temp/saate.txt
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
}

function compare_line_count() {
    local lc_uusi=$(cat ./temp/$1_uusi.txt | wc -l)
    local lc_vanha=$(cat ./data/$1.txt | wc -l)
    if [ $lc_uusi -ge $lc_vanha ]; then
        mv ./temp/$1_uusi.txt ./data/$1.txt
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
    dl_file $file
    encoding_to_utf8 ./temp/$file.txt

    # Odota latauksien välillä
    [ $i -lt $(($len - 1)) ] && sleep 5
    i=$(($i + 1))
done
unset i len filet

# $ajopvm muuttuja
hae_ajopvm

# Tarkista, onko ensimmäinen kerta kun tiedostot haetaan. Jos ei, niin tallena datat uutena.
if [ ! -f ./edellinen_ajo/saate.txt ] && [ ! -f ./data/tehdyt_ajot.txt ]; then
    echo "$current_date Edellisen ajon saatetta ei löytynyt. Tallennetaan datat uutena." >> run.log

    mkdir -p ./data
    mkdir -p ./edellinen_ajo

    filet=("atc")
    for file in "${filet[@]}"; do
        # Lisää ajopvm sarake ja arvot
        { head -1 ./temp/$file.txt \
            | awk '{ printf "AJOPVM;"; print }'; sed -e 1d ./temp/$file.txt | awk -v ajopvm="$ajopvm" '{ printf ajopvm";"; print }' ; } \
            | cat > ./temp/${file}_temp.txt \
            && mv ./temp/${file}_temp.txt ./temp/$file.txt

        cp ./temp/$file.txt ./data/$file.txt
        cp ./temp/$file.txt ./edellinen_ajo/$file.txt

        echo "$current_date ./temp/$file kopiotu ./data ./edellinen_ajo" >> run.log
    done

    cp ./temp/saate.txt ./data/tehdyt_ajot.txt
    cp ./temp/saate.txt ./edellinen_ajo/saate.txt
    echo "$current_date ./temp/saate.txt kopiotu ./data ./edellinen_ajo" >> run.log

    # Tee backupit
    echo "$current_date Tehdään backupit ./backup" >> run.log
    mkdir -p ./backup/temp
    cp -r ./edellinen_ajo/* ./backup/edellinen_ajo/
    cp -r ./data/* ./backup/data/
    cp -r ./temp/* ./backup/temp/

    # rm -rf ./temp

    echo -e "$current_date Datat tallennettu uutena.\n" >> run.log
    exit 0
fi

# Tarkista, onko saate identtinen edellisen kanssa
if [ "$(cmp --silent ./edellinen_ajo/saate.txt ./temp/saate.txt; echo $?)" -eq 0 ]; then
    echo -e "$current_date Ei päivitystä edelliseen Fimean ajoon.\n" >> run.log
    exit 0
fi

# TODO loop ja funktio? Esim. sort_var="$-k2,2 -k1,1" && sort -t';' $sort_var -o output.txt
# Ota talteen uudet rivit
echo "$current_date Otetaan talteen uudet uniikit rivit atc..." >> run.log

# Poista ajopvm edellisen ajon tiedostosta ja ota uudet uniikit rivit
new_rows=$(
    { cut --complement -d";" -f1 ./edellinen_ajo/atc.txt; cat ./temp/atc.txt; } \
        | sort | uniq -u
)

lc_new_rows=$(echo "$new_rows" | wc -l)
if [ $lc_new_rows -gt 0 ]; then
    # Lisää ajopvm arvot
    new_rows=$(echo "$new_rows" | awk -v ajopvm="$ajopvm" '{ printf ajopvm";"; print }')

    # Lisää myös ajopvm sarake ja arvot
    # TODO tee tästä funktio
    { head -1 ./temp/atc.txt \
        | awk '{ printf "AJOPVM;"; print }'; sed -e 1d ./temp/atc.txt | awk -v ajopvm="$ajopvm" '{ printf ajopvm";"; print }' ; } \
        | cat > ./temp/atc_temp.txt \
        && mv ./temp/atc_temp.txt ./temp/atc.txt

    # 1) Ota header pois; 2) yhdistä uniikit rivit; 3) sort; 4) yhdistä header ja sortatut rivit
    # TODO tee tästä funktio
    echo "$current_date Lisätään uniikit rivit dataan..." >> run.log
    { sed -e 1d ./data/atc.txt; echo "$new_rows"; } \
        | sort -t';' -k3,3 -k2,2 -o ./temp/atc_temp.txt \
        && head -1 ./data/atc.txt \
        | cat - ./temp/atc_temp.txt > ./temp/atc_uusi.txt

    rm -f ./temp/atc_temp.txt

    # Tarkista että päivitetyssä tiedostossa vähintään saman verran rivejä kuin vanhassa.
    # Jos on, niin päivitä tiedosto.
    compare_line_count "atc"
else
    echo "$current_date atc.txt uusien uniikkien rivien määrä 0. Ei tarvetta päivittää." >> run.log
fi

# Korvaa ./edellinen_ajo uudella ajolla
echo "$current_date Korvataan ./edellinen_ajo uudella ajolla." >> run.log
cp ./temp/saate.txt ./edellinen_ajo/saate.txt
cp ./temp/atc.txt ./edellinen_ajo/atc.txt


# Lisää saate tehtyihin ajoihin TODO pitäisikö siirtää myöhemmäksi
cat ./temp/saate.txt >> ./data/tehdyt_ajot.txt

# Backup temp ennen tyhjennystä
cp -r ./temp/* ./backup/temp/

echo "Script ajettu $(date +%y-%m-%d' '%T)" > ./edellinen_ajo/skripti_ajettu_pvm.txt
echo -e "$current_date Script ajo valmis.\n" >> run.log
