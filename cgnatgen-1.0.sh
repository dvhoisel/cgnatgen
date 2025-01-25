#!/bin/bash
# cgnatgen - versao 1.0 por Daniel Hoisel
# Licenciado sob a GPL 3.0

# Verifica se o dialog está instalado
if ! command -v dialog &> /dev/null; then
    echo "Erro: dialog não está instalado. Instale com 'sudo apt-get install dialog'"
    exit 1
fi

# Funções de conversão IP/Inteiro
ip_to_int() {
    local ip=$1
    IFS='.' read -r a b c d <<< "$ip"
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

int_to_ip() {
    local int=$1
    echo "$(( (int >> 24) & 255 )).$(( (int >> 16) & 255 )).$(( (int >> 8) & 255 )).$(( int & 255 ))"
}

network_address() {
    local ip_int=$1
    local mask=$2
    echo $(( ip_int & (0xFFFFFFFF << (32 - mask)) ))
}

# Validação de CIDR
validate_cidr() {
    local cidr_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'
    if [[ ! $1 =~ $cidr_regex ]]; then
        dialog --msgbox "Formato inválido: $1\nUse: IP/CIDR (ex: 100.64.0.0/23)" 8 50
        return 1
    fi
    
    IFS='/' read -r ip mask <<< "$1"
    IFS='.' read -r a b c d <<< "$ip"
    
    for octet in $a $b $c $d; do
        if (( octet < 0 || octet > 255 )); then
            dialog --msgbox "IP inválido: $ip\nOcteto deve estar entre 0-255" 8 50
            return 1
        fi
    done
    
    if (( mask < 8 || mask > 30 )); then
        dialog --msgbox "CIDR inválido: $mask\nMáscara deve estar entre 8-30" 8 50
        return 1
    fi
    
    return 0
}

# Verificação de IPs privados
is_private_ip() {
    local ip_int=$(ip_to_int $1)
    
    (( ip_int >= 0x0A000000 && ip_int <= 0x0AFFFFFF )) && return 0   # 10.0.0.0/8
    (( ip_int >= 0xAC100000 && ip_int <= 0xAC1FFFFF )) && return 0   # 172.16.0.0/12
    (( ip_int >= 0xC0A80000 && ip_int <= 0xC0A8FFFF )) && return 0   # 192.168.0.0/16
    (( ip_int >= 0x64400000 && ip_int <= 0x647FFFFF )) && return 0   # 100.64.0.0/10
    
    return 1
}

# Verificação de IPs públicos
is_public_ip() {
    ! is_private_ip $1 && return 0
    return 1
}

# Interface de entrada de dados
get_input() {
    declare -g privado_ip privado_mask publico_prefixes portas_por_ip ratio total_public_ips

    while true; do
        local tempfile1=$(mktemp)
        dialog --title "cgnatgen - versao 1.0 por Daniel Hoisel" \
            --form "Insira os blocos de IP:" \
            12 66 3 \
            "Bloco Privado (ex: 100.64.0.0/23):" 1 1 "" 1 36 36 0 \
            "Bloco Público (ex: 200.20.0.0/28):" 2 1 "" 2 36 36 0 \
            "Blocos públicos adicionais (1-19):" 3 1 "" 3 36 36 0 \
            2> "$tempfile1"

        [ $? -ne 0 ] && { rm -f "$tempfile1"; clear; exit 1; }

        IFS=$'\n' read -d '' -r privado_prefix publico_prefix1 num_additional < "$tempfile1"
        rm -f "$tempfile1"

        [[ -z "$num_additional" ]] && num_additional=0

        if ! [[ "$num_additional" =~ ^[0-9]+$ ]] || (( num_additional < 0 || num_additional > 19 )); then
            dialog --msgbox "Número de blocos adicionais inválido!\nDeve ser entre 0-19." 8 50
            continue
        fi

        additional_public=()
        if (( num_additional > 0 )); then
            local tempfile2=$(mktemp)
            local form_args=()
            for ((i=1; i<=num_additional; i++)); do
                form_args+=("Bloco Público Adicional $i:")
                form_args+=("$i" 1 "" "$i" 30 30 0)
            done

            dialog --title "Blocos Públicos Adicionais" \
                --form "Insira os blocos adicionais:" \
                $((num_additional + 7)) 60 $num_additional \
                "${form_args[@]}" \
                2> "$tempfile2"

            IFS=$'\n' read -d '' -r -a additional_public < "$tempfile2"
            rm -f "$tempfile2"
        fi

        validate_cidr "$privado_prefix" || continue
        IFS='/' read -r privado_ip privado_mask <<< "$privado_prefix"
        if ! is_private_ip "$privado_ip"; then
            dialog --msgbox "IP Privado inválido!\nDeve ser RFC 1918 ou CGNAT (100.64.0.0/10)" 8 50
            continue
        fi

        validate_cidr "$publico_prefix1" || continue
        IFS='/' read -r publico_ip publico_mask <<< "$publico_prefix1"
        if ! is_public_ip "$publico_ip"; then
            dialog --msgbox "IP Público 1 inválido!\nNão pode ser privado/reservado" 8 50
            continue
        fi

        publico_prefixes=("$publico_prefix1")
        local valid=true
        for block in "${additional_public[@]}"; do
            validate_cidr "$block" || { valid=false; break; }
            IFS='/' read -r ip mask <<< "$block"
            if ! is_public_ip "$ip"; then
                dialog --msgbox "IP Público adicional inválido: $block\nNão pode ser privado/reservado" 8 50
                valid=false
                break
            fi
            publico_prefixes+=("$block")
        done
        $valid || continue

        total_public_ips=0
        for block in "${publico_prefixes[@]}"; do
            IFS='/' read -r ip mask <<< "$block"
            total_public_ips=$(( total_public_ips + 2**(32 - mask) ))
        done

        if (( (total_public_ips & (total_public_ips - 1)) != 0 )); then
            dialog --msgbox "Total de IPs públicos ($total_public_ips) não é potência de 2!" 8 50
            continue
        fi

        local private_total=$(( 2**(32 - privado_mask) ))
        ratio=$(( private_total / total_public_ips ))
        if (( private_total % total_public_ips != 0 )); then
            dialog --msgbox "Blocos incompatíveis!\nIPs privados: $private_total\nIPs públicos: $total_public_ips" 8 50
            continue
        fi

        portas_por_ip=$(( 64000 / ratio ))
        if (( 64000 % ratio != 0 )); then
            dialog --msgbox "Relação inválida!\n64000 portas não são divisíveis por $ratio" 8 50
            continue
        fi

        break
    done
}

# Gerador de regras NAT
generate_rules() {
    local privado_net=$(network_address $(ip_to_int "$privado_ip") "$privado_mask")
    declare -a jump_rules nat_rules

    echo "/ip firewall nat" > mk-cgnat.rsc
    echo "add chain=srcnat action=jump jump-target=CGNAT src-address=${privado_prefix} comment=\"CGNAT: ${privado_prefix} → Blocos Públicos: ${publico_prefixes[*]} | Total IPs: ${total_public_ips} | Qtd Blocos: ${#publico_prefixes[@]} | Portas/IP: ${portas_por_ip}\"" >> mk-cgnat.rsc

    for block in "${publico_prefixes[@]}"; do
        IFS='/' read -r publico_ip publico_mask <<< "$block"
        local publico_net=$(network_address $(ip_to_int "$publico_ip") "$publico_mask")
        local num_ips=$(( 2 ** (32 - publico_mask) ))

        for (( i=0; i < num_ips; i++ )); do
            local current_public_ip=$(int_to_ip $(( publico_net + i )) )
            local private_subnet_start=$(( privado_net + (i * ratio) ))
            local subnet_mask=$(( 32 - $(echo "l($ratio)/l(2)" | bc -l | cut -d. -f1) ))
            local subnet_cidr="$(int_to_ip $private_subnet_start)/$subnet_mask"

            jump_rules+=("add chain=CGNAT action=jump jump-target=\"CGNAT-$current_public_ip\" src-address=\"$subnet_cidr\" comment=\"Sub-rede: $subnet_cidr → $current_public_ip\"")
            nat_rules+=("add chain=\"CGNAT-$current_public_ip\" action=src-nat protocol=icmp src-address=\"$subnet_cidr\" to-address=$current_public_ip comment=\"ICMP: $subnet_cidr → $current_public_ip\"")

            for (( j=0; j < ratio; j++ )); do
                local private_ip=$(int_to_ip $(( private_subnet_start + j )) )
                local porta_inicio=$(( 1500 + (j * portas_por_ip) ))
                local porta_fim=$(( porta_inicio + portas_por_ip - 1 ))

                # Verifica se as portas ultrapassam 65535
                if (( porta_fim > 65535 )); then
                    dialog --msgbox "ERRO: Portas excedem o limite máximo (65535) para o IP $current_public_ip" 8 60
                    exit 1
                fi

                nat_rules+=("add chain=\"CGNAT-$current_public_ip\" action=src-nat protocol=tcp src-address=$private_ip to-address=$current_public_ip to-ports=$porta_inicio-$porta_fim comment=\"TCP: $private_ip → $current_public_ip:$porta_inicio-$porta_fim\"")
                nat_rules+=("add chain=\"CGNAT-$current_public_ip\" action=src-nat protocol=udp src-address=$private_ip to-address=$current_public_ip to-ports=$porta_inicio-$porta_fim comment=\"UDP: $private_ip → $current_public_ip:$porta_inicio-$porta_fim\"")
            done
        done
    done

    printf "%s\n" "${jump_rules[@]}" >> mk-cgnat.rsc
    printf "%s\n" "${nat_rules[@]}" >> mk-cgnat.rsc
}

# Execução principal
get_input
generate_rules

# Exibe resumo
publico_list=$(IFS=,; echo "${publico_prefixes[*]}")
dialog --title "Concluído" \
       --msgbox "Arquivo mk-cgnat.rsc gerado com sucesso!\n\n- Bloco Privado: ${privado_prefix}\n- Blocos Públicos: ${publico_list}\n- Total IPs Públicos: ${total_public_ips}\n- Quantidade de Blocos: ${#publico_prefixes[@]}\n- Portas por IP: ${portas_por_ip}" \
       14 70

clear