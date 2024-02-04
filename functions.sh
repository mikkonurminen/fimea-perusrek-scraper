#!/bin/bash

function extract_link() {
    echo "$current_date Haetaan linkki $1..." >> run.log
    local link=$(cat ./temp/fimea.html | grep -w "${1}.txt" | sed -e 's/.*href=\"\(.*\)\">.*/\1/')
    echo "https://fimea.fi${link}"
}

function dl_file() {
    echo "$current_date Ladataan $1..." >> run.log
    local link=$(extract_link ${1})

    echo "$current_date wget $link" >> run.log
    # wget -nv -O ./temp/$1.txt \
        #     --no-cache --no-cookies --header="Accept: text/html" \
        #     --user-agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:21.0) Gecko/20100101 Firefox/21.0" \
        #     $link 2>>run.log
    #
    # if [ $? -ne 0 ]; then
    #     echo "Url virhe latauksessa $file.txt" >> run.log
    #     echo 1 && return 1
    # fi

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

    echo "$ajopvm"
}

function add_ajopvm_column() {
    { head -1 ./temp/$1.txt \
        | awk '{ printf "AJOPVM;"; print }'; sed -e 1d ./temp/$1.txt | awk -v ajopvm="$ajopvm" '{ printf ajopvm";"; print }' ; } \
        | cat > ./temp/$1_temp.txt \
        && mv ./temp/$1_temp.txt ./temp/$1.txt
}

function add_unique_rows() {
    # 1) Ota header pois; 2) yhdistä uniikit rivit; 3) sort; 4) yhdistä header ja sortatut rivit
    echo "$current_date Lisätään uniikit rivit dataan..." >> run.log
    { sed -e 1d ./data/$1.txt; echo "$new_rows"; } \
        | sort -t';' $2 -o ./temp/$1_temp.txt \
        && head -1 ./data/$1.txt \
        | cat - ./temp/$1_temp.txt > ./temp/$1.txt
}

function compare_line_count() {
    local lc_uusi=$(cat ./temp/$1.txt | wc -l)
    local lc_vanha=$(cat ./data/$1.txt | wc -l)
    if [ $lc_uusi -lt $lc_vanha ]; then
        echo "$current_date Virhe: päivitetyn $1.txt rivien määrä pienempi kuin edellisen." >> run.log
        exit 1
    fi
}
