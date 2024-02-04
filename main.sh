#!/bin/bash

source ./functions.sh

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
# wget -nv -O ./temp/fimea.html \
    #     --no-cache --no-cookies --header="Accept: text/html" \
    #     --user-agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:21.0) Gecko/20100101 Firefox/21.0" \
    #     https://fimea.fi/laakehaut_ja_luettelot/perusrekisteri 2>>run.log


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
ajopvm=$(hae_ajopvm)

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

# Päivitä tiedostot uusilla riveillä
filet=("atc")
sort_var=("-k3,3 -k2,2")
i=$(echo 0)
for file in "${filet[@]}"; do
    # Ota talteen uudet rivit
    echo "$current_date Otetaan talteen uudet uniikit rivit $file..." >> run.log

    # Poista ajopvm edellisen ajon tiedostosta ja ota uudet uniikit rivit
    new_rows=$(
        { cut --complement -d";" -f1 ./edellinen_ajo/$file.txt; cat ./temp/$file.txt; } \
            | sort | uniq -u
    )

    lc_new_rows=$(echo "$new_rows" | wc -l)
    if [ $lc_new_rows -gt 0 ]; then
        # Lisää ajopvm arvot uusiin riveihin
        new_rows=$(echo "$new_rows" | awk -v ajopvm="$ajopvm" '{ printf ajopvm";"; print }')

        echo "$new_rows" > ./temp/${file}_uudet_rivit.txt

        # Lisää ajopvm sarake ja arvot tiedostoon
        add_ajopvm_column "$file"

        # Lisää uudet uniikit rivit dataan
        add_unique_rows "$file" "${sort_var[$i]}"

        rm -f ./temp/${file}_temp.txt

        # Tarkista että päivitetyssä tiedostossa vähintään saman verran rivejä kuin vanhassa.
        # Jos on, niin päivitä tiedosto.
        compare_line_count "$file"
        mv ./temp/$file.txt ./data/$file.txt
        echo "$current_date ./data/$file.txt päivitetty." >> run.log

        exit 1
    else
        echo "$current_date $file.txt uusien uniikkien rivien määrä 0. Ei tarvetta päivittää." >> run.log
    fi

    i=$(($i + 1))
done
unset filet i sort_var new_rows

# Korvaa ./edellinen_ajo uudella ajolla
echo "$current_date Korvataan ./edellinen_ajo uudella ajolla." >> run.log
# TODO Loop
cp ./temp/saate.txt ./edellinen_ajo/saate.txt
cp ./temp/atc.txt ./edellinen_ajo/atc.txt

cp ./temp/atc_uudet_rivit ./edellinen_ajo/atc_uudet_rivit.txt

# Lisää saate tehtyihin ajoihin TODO pitäisikö siirtää myöhemmäksi
cat ./temp/saate.txt >> ./data/tehdyt_ajot.txt

# Backup temp ennen tyhjennystä
cp -r ./temp/* ./backup/temp/

echo "Script ajettu $(date +%y-%m-%d' '%T)" > ./edellinen_ajo/skripti_ajettu_pvm.txt
echo -e "$current_date Script ajo valmis.\n" >> run.log
