# cgnatgen
Gerador de regras de CGNAT tipo porta fixa vertical para o Mikrotik

Depois de procurar vários scripts na web, e não encontrar nenhum que fizesse exatamente o que eu queria,
fiz esse em bash, que me atende. Espero que possa servir para outros.

Depende das ferramentas `dialog`, `bc`, `awk` (ou `gawk`) e `stdbuf` (coreutils).

As versões até a 0.2-beta utilizavam `ipcalc` para validar IPs. A versão 1.0 realiza essas validações internamente e não depende mais dele.

Para executar, rode `./cgnatgen-1.0.sh`.

### Screenshots v0.1

![Screenshot da entrada do prefixo privado](/cgnatgen.png "Bloco privado")

![Screenshot da entrada do prefixo público](/cgnatgen2.png "Bloco público")

![Screenshot da saída com informações](/cgnatgen3.png "Informações de saída")

### Screenshots v0.2-beta

![Screenshot da entrada dos blocos públicos](/cgnatgen4.png "Blocos públicos")

TODO: 
- Gerar regras com portas flexíveis, vinculando cada faixa a um bloco privado ou IP público. 
- Aceitar mais de um prefixo público para um prefixo privado

  A versão 0.2-beta já aceita - faltam algumas validações
