#!/bin/bash
# cgnatgen 1.0 - por Daniel Hoisel sob GPL 3.0

# Verifica dependências
check_dependencies() {
    local missing=()
    
    declare -A required=(
        [dialog]="Interface de usuário textual"
        [bc]="Cálculos matemáticos"
        [awk]="Processamento de texto"
        [stdbuf]="Controle de buffer (coreutils)"
    )
    
    for cmd in dialog bc awk stdbuf; do
        if ! command -v $cmd &> /dev/null; then
            missing+=("$cmd (${required[$cmd]})")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Erro: dependências não instaladas:"
        for pkg in "${missing[@]}"; do
            echo "  - $pkg"
        done
        echo -e "\nInstale com:"
        echo "  sudo apt install dialog bc gawk coreutils"
        exit 1
    fi
}

check_dependencies

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

check_overlap() {
    local cidr1=$1
    local cidr2=$2
    
    IFS='/' read -r ip1 mask1 <<< "$cidr1"
    IFS='/' read -r ip2 mask2 <<< "$cidr2"
    
    local net1=$(network_address $(ip_to_int "$ip1") "$mask1")
    local net2=$(network_address $(ip_to_int "$ip2") "$mask2")
    
    local size1=$(( 2 ** (32 - mask1) ))
    local size2=$(( 2 ** (32 - mask2) ))
    
    local end1=$(( net1 + size1 - 1 ))
    local end2=$(( net2 + size2 - 1 ))
    
    if (( (net1 >= net2 && net1 <= end2) || (net2 >= net1 && net2 <= end1) )); then
        return 0
    fi
    
    return 1
}

is_private_ip() {
    local ip_int=$(ip_to_int $1)
    
    (( ip_int >= 0x0A000000 && ip_int <= 0x0AFFFFFF )) && return 0
    (( ip_int >= 0xAC100000 && ip_int <= 0xAC1FFFFF )) && return 0
    (( ip_int >= 0xC0A80000 && ip_int <= 0xC0A8FFFF )) && return 0
    (( ip_int >= 0x64400000 && ip_int <= 0x647FFFFF )) && return 0
    
    return 1
}

is_public_ip() {
    ! is_private_ip $1 && return 0
    return 1
}

get_input() {
    declare -g privado_ip privado_mask publico_prefixes portas_por_ip ratio total_public_ips

    while true; do
        local tempfile=$(mktemp)
        
        dialog --title "cgnatgen 1.0 - por Daniel Hoisel" \
            --form "Insira os blocos de IP:\n(Campos públicos adicionais são opcionais)" \
            28 64 21 \
            "Bloco Privado (ex: 100.64.0.0/22): *" 1 1 "" 1 38 20 0 \
            "Bloco Público (ex: 200.20.0.0/27): *" 2 1 "" 2 38 20 0 \
            "Bloco Público 2:"                    3 1 "" 3 38 20 0 \
            "Bloco Público 3:"                    4 1 "" 4 38 20 0 \
            "Bloco Público 4:"                    5 1 "" 5 38 20 0 \
            "Bloco Público 5:"                    6 1 "" 6 38 20 0 \
            "Bloco Público 6:"                    7 1 "" 7 38 20 0 \
            "Bloco Público 7:"                    8 1 "" 8 38 20 0 \
            "Bloco Público 8:"                    9 1 "" 9 38 20 0 \
            "Bloco Público 9:"                    10 1 "" 10 38 20 0 \
            "Bloco Público 10:"                   11 1 "" 11 38 20 0 \
            "Bloco Público 11:"                   12 1 "" 12 38 20 0 \
            "Bloco Público 12:"                   13 1 "" 13 38 20 0 \
            "Bloco Público 13:"                   14 1 "" 14 38 20 0 \
            "Bloco Público 14:"                   15 1 "" 15 38 20 0 \
            "Bloco Público 15:"                   16 1 "" 16 38 20 0 \
            "Bloco Público 16:"                   17 1 "" 17 38 20 0 \
            "Bloco Público 17:"                   18 1 "" 18 38 20 0 \
            "Bloco Público 18:"                   19 1 "" 19 38 20 0 \
            "Bloco Público 19:"                   20 1 "" 20 38 20 0 \
            "Bloco Público 20:"                   21 1 "" 21 38 20 0 \
            2> "$tempfile"

        [ $? -ne 0 ] && { rm -f "$tempfile"; clear; exit 1; }

        IFS=$'\n' read -d '' -r -a inputs < "$tempfile"
        rm -f "$tempfile"

        privado_prefix="${inputs[0]}"
        publico_prefixes=("${inputs[@]:1:20}")

        if ! validate_cidr "$privado_prefix" || ! is_private_ip "${privado_prefix%%/*}"; then
            dialog --msgbox "Bloco Privado inválido!\nDeve ser RFC 1918 ou CGNAT (ex: 100.64.0.0/10)" 8 50
            continue
        fi
        IFS='/' read -r privado_ip privado_mask <<< "$privado_prefix"

        local temp_public=()
        for ((i=0; i<20; i++)); do
            block="${publico_prefixes[$i]}"
            block_number=$((i + 1))
            
            if (( block_number == 1 )) && [[ -z "$block" ]]; then
                dialog --msgbox "Bloco Público 1 é obrigatório!" 8 50
                continue 2
            fi
            
            if (( block_number > 1 )) && [[ -z "$block" ]]; then 
                continue
            fi
            
            if ! validate_cidr "$block" || ! is_public_ip "${block%%/*}"; then
                dialog --msgbox "Bloco Público $block_number inválido: $block\nFormato: IP/CIDR (8-30) e deve ser público." 8 60
                continue 2
            fi
            
            temp_public+=("$block")
        done
        
        publico_prefixes=("${temp_public[@]}")

        overlap_found=false
        for ((i=0; i<${#publico_prefixes[@]}; i++)); do
            for ((j=i+1; j<${#publico_prefixes[@]}; j++)); do
                if check_overlap "${publico_prefixes[i]}" "${publico_prefixes[j]}"; then
                    dialog --msgbox "Blocos públicos sobrepostos detectados:\n\n${publico_prefixes[i]}\n${publico_prefixes[j]}" 10 60
                    overlap_found=true
                    break 2
                fi
            done
        done

        if $overlap_found; then
            continue
        fi

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
        if (( private_total % total_public_ips != 0 )); then
            dialog --msgbox "Blocos incompatíveis!\nIPs privados: $private_total\nIPs públicos: $total_public_ips" 8 50
            continue
        fi
        ratio=$(( private_total / total_public_ips ))

        if (( 64000 % ratio != 0 )); then
            dialog --msgbox "Relação inválida!\n64000 portas não são divisíveis por $ratio" 8 50
            continue
        fi
        portas_por_ip=$(( 64000 / ratio ))

        break
    done
}

generate_rules() {
    local privado_net=$(network_address $(ip_to_int "$privado_ip") "$privado_mask")
    declare -a jump_rules nat_rules
    local current_private_offset=0
    declare -A allocated_subnets

    > mk-cgnat.rsc || {
        dialog --msgbox "Erro: Não foi possível criar o arquivo mk-cgnat.rsc" 8 60
        exit 1
    }

    {
        echo "/ip firewall nat"
        echo "add chain=srcnat action=jump jump-target=CGNAT src-address=${privado_prefix} comment=\"CGNAT: ${privado_prefix} → Blocos Públicos: ${publico_prefixes[*]} | Total IPs: ${total_public_ips} | Qtd Blocos: ${#publico_prefixes[@]} | Portas/IP: ${portas_por_ip}\""
    } >> mk-cgnat.rsc

    for block in "${publico_prefixes[@]}"; do
        IFS='/' read -r publico_ip publico_mask <<< "$block"
        local publico_net=$(network_address $(ip_to_int "$publico_ip") "$publico_mask")
        local num_ips=$(( 2 ** (32 - publico_mask) ))

        for (( i=0; i < num_ips; i++ )); do
            local current_public_ip=$(int_to_ip $(( publico_net + i )) )
            local private_subnet_start=$(( privado_net + current_private_offset ))
            
            local subnet_mask=$(LC_NUMERIC=C printf "scale=10; l($ratio)/l(2)\n" | bc -l | awk '{printf "%d\n", 32 - int($0 + 0.5)}')
            local subnet_cidr="$(int_to_ip $private_subnet_start)/$subnet_mask"

            if [[ -n "${allocated_subnets[$subnet_cidr]}" ]]; then
                dialog --msgbox "ERRO: Sobreposição detectada na sub-rede $subnet_cidr" 8 60
                exit 1
            fi
            allocated_subnets["$subnet_cidr"]=1

            jump_rules+=("add chain=CGNAT action=jump jump-target=\"CGNAT-$current_public_ip\" src-address=\"$subnet_cidr\" comment=\"Sub-rede: $subnet_cidr → $current_public_ip\"")
            nat_rules+=("add chain=\"CGNAT-$current_public_ip\" action=src-nat protocol=icmp src-address=\"$subnet_cidr\" to-address=$current_public_ip comment=\"ICMP: $subnet_cidr → $current_public_ip\"")

            for (( j=0; j < ratio; j++ )); do
                local private_ip=$(int_to_ip $(( private_subnet_start + j )) )
                local porta_inicio=$(( 1500 + j * portas_por_ip ))
                local porta_fim=$(( porta_inicio + portas_por_ip - 1 ))

                if (( porta_fim > 65535 )); then
                    dialog --msgbox "ERRO: Portas excedem o limite máximo (65535) para o IP $current_public_ip" 8 60
                    exit 1
                fi

                nat_rules+=("add chain=\"CGNAT-$current_public_ip\" action=src-nat protocol=tcp src-address=$private_ip to-address=$current_public_ip to-ports=$porta_inicio-$porta_fim comment=\"TCP: $private_ip → $current_public_ip:$porta_inicio-$porta_fim\"")
                nat_rules+=("add chain=\"CGNAT-$current_public_ip\" action=src-nat protocol=udp src-address=$private_ip to-address=$current_public_ip to-ports=$porta_inicio-$porta_fim comment=\"UDP: $private_ip → $current_public_ip:$porta_inicio-$porta_fim\"")
            done

            current_private_offset=$(( current_private_offset + ratio ))
        done
    done

    # Escreve regras com quebras de linha garantidas
    printf "%s\n" "${jump_rules[@]}" | stdbuf -oL tee -a mk-cgnat.rsc >/dev/null
    printf "%s\n" "${nat_rules[@]}" | stdbuf -oL tee -a mk-cgnat.rsc >/dev/null
}

get_input
generate_rules

publico_list=$(IFS=,; echo "${publico_prefixes[*]}")
dialog --title "Concluído" \
       --msgbox "Arquivo mk-cgnat.rsc gerado com sucesso!\n\n- Bloco Privado: ${privado_prefix}\n- Blocos Públicos: ${publico_list}\n- Total IPs Públicos: ${total_public_ips}\n- Quantidade de Blocos: ${#publico_prefixes[@]}\n- Portas por IP: ${portas_por_ip}" \
       14 70

clear
