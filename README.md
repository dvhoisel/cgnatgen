# cgnatgen
Gerador de regras de CGNAT tipo porta fixa vertical para o Mikrotik

Depois de procurar vários scripts na web, e não encontrar nenhum que fizesse exatamente o que eu queria,
fiz esse em bash, que me atende. Espero que possa servir para outros.

Depende do dialog

Usa o ipcalc para fazer algumas validações de IP.

### Screenshots

![Screenshot da entrada do prefixo privado](/cgnatgen.png "Prefixo privado")

![Screenshot da entrada do prefixo público](/cgnatgen2.png "Prefixo público")

![Screenshot da saída com informações](/cgnatgen3.png "Informações de saída")


TODO: 
- Substituir cut por separação de variável em matriz
- Aceitar mais de um prefixo público para um prefixo privado
