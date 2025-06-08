#!/bin/bash
# Desenvolvido por Daniel Hoisel
# Licenciado sob a GPL 3.0
versao="0.2-beta"
autor="Daniel Hoisel"
if which dialog >/dev/null
then
if [[ $1 ]]
then
    arquivo=$1
else
    arquivo="mk-cgnat.rsc"
fi
while : ; do
    if which ipcalc >/dev/null; then
        aviso=""
    else
        aviso=" o programa ipcalc tem que estar instalado,
                para que as validações sejam feitas.
                Confira a entrada de dados."
    fi
	entrada=$( dialog --stdout --backtitle 'cgnatgen' --title "cgnatgen - Desenvolvido por $autor - Versão: $versao" \
    --inputbox "$aviso
                Defina o nome do arquivo, executando o programa
                com o nome como parâmetro. Ex.:
                ./cgnatgen.sh arquivo.rsc
                Se não for definido, será gerado como mk-cgnat.rsc
                Atualmente o nome é: $arquivo
                Informe o bloco privado, com a máscara.
                Ex.: 100.100.0.0/20" 0 0 )
	if which ipcalc >/dev/null; then
        ipcalc -cbn $entrada | grep Network | cut -f2 -d: | grep $entrada || { dialog --stdout --backtitle 'cgnatgen' --title "cgnatgen - Desenvolvido por $autor - Versão: $versao" --msgbox "Endereço IP ou de rede inválidos" 0 0; exit; }
    else
        dialog --stdout --sleep 2 --backtitle 'cgnatgen' --title "cgnatgen - Desenvolvido por $autor - Versão: $versao" --infobox "ipcalc não está instalado. A validação não foi feita" 0 0
    fi
    IFS='/' read -r ipprivado mascaraprivado <<<"$entrada"
    if [[ $mascaraprivado -gt 25 ]]
    then
        dialog --stdout --msgbox 'Quem faz CGNAT com tão poucos IPs?' 0 0
        exit
    fi
    entrada=$( dialog --stdout --backtitle 'cgnatgen' \
                --title "cgnatgen - Desenvolvido por $autor - Versão: $versao" \
                --inputbox "
                PORTAS X BLOCO PÚBLICO NECESSÁRIO
                -----------------------------------
                0500: /$(( $mascaraprivado + 7 )) = $((2**$((32 - $(($mascaraprivado + 7)))))) IPs
                1000: /$(( $mascaraprivado + 6 )) = $((2**$((32 - $(($mascaraprivado + 6)))))) IPs
                2000: /$(( $mascaraprivado + 5 )) = $((2**$((32 - $(($mascaraprivado + 5)))))) IPs
                4000: /$(( $mascaraprivado + 4 )) = $((2**$((32 - $(($mascaraprivado + 4)))))) IPs
                8000: /$(( $mascaraprivado + 3 )) = $((2**$((32 - $(($mascaraprivado + 3)))))) IPs 
                
                Informe o(s) bloco(s) público(s), com a máscara.
                Ex.: 200.200.0.0/25
                Ex.: 200.200.0.0/26 200.200.1.0/27 200.200.2.0/27
                
                Obs.: Quando informado mais de um bloco,
                para efeito do cálculo da quantidade de portas,
                será computada a quantidade total de IPs,
                que deve ser potência na base 2." 0 0 )
    echo "/ip firewall nat" > $arquivo
    echo "add chain=srcnat action=jump jump-target=CGNAT src-address=$ipprivado/$mascaraprivado comment=\"CGNAT por cgnatgen. Do bloco privado: $ipprivado/$mascaraprivado para o(s) bloco(s) publico(s): $entrada - Desative essa regra para desativar o CGNAT\"" >> $arquivo
	quantidadepublico=0
    for blocopublico in ${entrada[*]} 
    do
    IFS='/' read -r ippublico mascarapublico <<<"$blocopublico"
    quantidadetotalpublico=$(($quantidadetotalpublico+2**$((32-$mascarapublico))))
    done
    function log2 {
    local l=0
    for (( w=$1-1 ; $w > 0; w >>= 1 )) ; do
        l=$(( $l+1 ))
    done
    echo $l
    }
    mascaratotalpublico=$(( 32 - $(log2 $quantidadetotalpublico) ))
    IFS='.' read -r ipprvpo ipprvso ipprvto ipprvqo <<<"$ipprivado" 
    for blocopublico in ${entrada[*]} 
    do
        if which ipcalc >/dev/null; then
            ipcalc -cbn $blocopublico | grep Network | cut -f2 -d: | grep $blocopublico || { dialog --stdout --backtitle 'cgnatgen' --title "cgnatgen - Desenvolvido por $autor - Versão: $versao" --infobox "Endereço IP ou de rede inválidos" 0 0 ; exit; }
        else
            dialog --stdout --sleep 2 --backtitle 'cgnatgen' --title "cgnatgen - Desenvolvido por $autor - Versão: $versao" --infobox "ipcalc não está instalado. A validação não foi feita" 0 0
        fi
        IFS='/' read -r ippublico mascarapublico <<<"$blocopublico"
        quantidadepublico=$((2**$((32-$mascarapublico))))
        quantidadeprivado=$((2**$((32-$mascaraprivado))))
        relacao=$(($quantidadeprivado/$quantidadetotalpublico))
        portas=$((64000/$relacao))
        if [[ $portas -lt 500 || $portas -gt 8000 ]]
        then
            aviso1="AVISO: A quantidade mínima e máxima de portas"
            aviso2="recomendada é 500 e 8000, respectivamente"
        fi
        dialog \
                    --cr-wrap \
                    --backtitle 'cgnatgen'   \
                    --title "cgnatgen - Desenvolvido por $autor - Versão: $versao" \
                    --infobox "
                    Gerando o arquivo $arquivo
                    Quantidade de IPs públicos: $quantidadetotalpublico
                    Quantidade de IPs privados: $quantidadeprivado
                    Relação entre público e privado: 1:$relacao
                    Quantidade de portas para cada IP privado: $portas
                    Quantidade de regras criadas: $(( ($quantidadetotalpublico * 2) + ($quantidadeprivado * 2) + 1 ))
                    $aviso1
                    $aviso2
                    Use IPv6
                    " 15 60
        mascarajump=$((32-($mascaratotalpublico-$mascaraprivado)))
        IFS='.' read -r ippubpo ippubso ippubto ippubqo <<<"$ippublico"
        comecoporta=1501
        y=1
        while [ $y -le $quantidadepublico ]
        do
            if [[ $ippubqo -gt 255 ]]
            then
                ippubqo=0
                ippubto=$(( $ippubto + 1))
            fi
            if [[ $ipprvqo -gt 255 ]]
            then
                ipprvqo=0
                ipprvto=$(( $ipprvto + 1))
            fi
            echo "add chain=CGNAT action=jump jump-target=\"CGNAT-$ippubpo.$ippubso.$ippubto.$ippubqo\" src-address=\"$ipprvpo.$ipprvso.$ipprvto.$ipprvqo/$mascarajump\" comment=\"CGNAT por cgnatgen - regra de JUMP do bloco privado: $ipprvpo.$ipprvso.$ipprvto.$ipprvqo/$mascarajump para o IP publico: $ippubpo.$ippubso.$ippubto.$ippubqo\"" >> $arquivo
            ippubqo=$(( $ippubqo + 1 ))
            ipprvqo=$(( $ipprvqo + $relacao ))
            y=$(( $y + 1 ))
        done
    done
    IFS='.' read -r ipprvpo ipprvso ipprvto ipprvqo <<<"$ipprivado"
    for blocopublico in ${entrada[*]} 
    do
        IFS='/' read -r ippublico mascarapublico <<<"$blocopublico"
        IFS='.' read -r ippubpo ippubso ippubto ippubqo <<<"$ippublico"
        y=1
        portainicial=$comecoporta
        while [ $y -le $quantidadepublico ]
        do
            if [[ $ippubqo -gt 255 ]]
            then
                ippubqo=0
                ippubto=$(( $ippubto + 1))
            fi
            if [[ $ipprvqo -gt 255 ]]
            then
                ipprvqo=0
                ipprvto=$(( $ipprvto + 1))
            fi
            echo "add chain=\"CGNAT-$ippubpo.$ippubso.$ippubto.$ippubqo\" action=src-nat protocol=icmp src-address=$ipprvpo.$ipprvso.$ipprvto.$ipprvqo/$mascarajump to-address=$ippubpo.$ippubso.$ippubto.$ippubqo comment=\"CGNAT - Protocolo: ICMP do bloco privado: $ipprvpo.$ipprvso.$ipprvto.$ipprvqo/$mascarajump para o IP publico: $ippubpo.$ippubso.$ippubto.$ippubqo\"" >> $arquivo
            x=1
            while [ $x -le $relacao ]
            do
                if [[ $ippubqo -gt 255 ]]
                then
                    ippubqo=0
                    ippubto=$(( $ippubto + 1))
                fi
                if [[ $ipprvqo -gt 255 ]]
                then
                    ipprvqo=0
                    ipprvto=$(( $ipprvto + 1))
                fi
                portafinal=$(( $portainicial + $portas - 1 ))
                echo "add chain=\"CGNAT-$ippubpo.$ippubso.$ippubto.$ippubqo\" action=src-nat protocol=tcp src-address=$ipprvpo.$ipprvso.$ipprvto.$ipprvqo to-address=$ippubpo.$ippubso.$ippubto.$ippubqo to-ports=$portainicial-$portafinal comment=\"CGNAT - Protocolo: TCP do IP privado: $ipprvpo.$ipprvso.$ipprvto.$ipprvqo para o IP publico: $ippubpo.$ippubso.$ippubto.$ippubqo, portas de $portainicial a $portafinal\"" >> $arquivo
                echo "add chain=\"CGNAT-$ippubpo.$ippubso.$ippubto.$ippubqo\" action=src-nat protocol=udp src-address=$ipprvpo.$ipprvso.$ipprvto.$ipprvqo to-address=$ippubpo.$ippubso.$ippubto.$ippubqo to-ports=$portainicial-$portafinal comment=\"CGNAT - Protocolo: UDP do IP privado: $ipprvpo.$ipprvso.$ipprvto.$ipprvqo para o IP publico: $ippubpo.$ippubso.$ippubto.$ippubqo, portas de $portainicial a $portafinal\"">> $arquivo
                portainicial=$(( $portainicial + $portas ))
                ipprvqo=$(( $ipprvqo + 1 ))
                x=$(( $x + 1 ))
            done
            portainicial=1501
            ippubqo=$(( $ippubqo + 1 ))
            y=$(( $y + 1 ))
        done
    done
    exit
done
else
    echo "cgnatgen - Desenvolvido por $autor - Versão: $versao
          dialog não instalado"
fi
