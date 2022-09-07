## Wordpress LoadBalancé

création : 01/06/2022
groupe 1 : Alain, Amine, Boubakar, Jéremy, Mahdi
liens sripts: 

[script.7z](:/9c342f15593d4512bea58e38bd758375)


* * *

### Table des matières

> - Objectif
> - Diagramme
> - Préambule
> - Créer un groupe de ressources
> - Créez un réseau virtuel
> - Créer une adresse IP publique
> - Créer un équilibrage de charge
> - Créer un groupe de sécurité réseau
> - Création de deux VM Debian 11
> - Créer une passerelle NAT
> - Céation Azure Database MariaDB (saas)
> - Régle NAT/PAT pour accés vm en ssh
> - Installation de Apache et PHP sur Debian11
> - Installation de Wordpress sur les vms
> - Azure Monitor
> - Test Load Balancing
> - Script de création ressources Azure
> - Script d'installation Lamp Wordpress
> - Problèmes rencontrés

* * *

## Objectif

- Installation par script Azure-Cli, hébergé sur GitLab
- 2 VMs Debian 11 avec Wordpress (IaaS)
- 1 Adresse IP publique
- 1 base de données MariaDb (SaaS)
- 1 load Balancer
- 1 Azure Monitor (Application Insight) pour WordPress
- BONUS 1 : Mettre en place un Reverse Proxy
- BONUS 2 : Ajouter du contenu dans WordPress

* * *

<img src=":/c6b3fca2dd8b4182b55c241d209514eb" alt="diagramv1.jpg" width="594" height="540">

* * *

## Préambule

- Pour la réalisaiton de ce projet nous avons opté pour une solution sans Bastion au profit d'une implementation de règle PAT pour connexion à nos vms en ssh en specifiant l'ip front et les ports assignés à chaque vm.
- Dans cette documentation sera detaillé le processus de creation des ressources en commande line interface. La méthode consiste à créer les ressources qui servent de base en premier, la ressource suivante fesant reférence à la précedente et ainsi de suite, comme plusieurs maillons d'une même chaine.
- Il est à noter que l'ordre des actions different de celui de la création en GUI, surtout pour la création des vms
    - en GUI, beaucoup plus d'action se font dans les onglets de creation de la vm.
    - en CLI, il faut preparer Network Security group, carte réseau en amont, et l'ajout au Backend Pool du load balancer en aval. Mais pour un résulat plus controlé et propre, avec un seul NSG par exemple.

* * *

## Créer un groupe de ressources

`az group create --location eastus --name $NomDuGroupe`

* * *

## Créez un réseau virtuel

Nous séléctionnons notre groupe de ressource ainsi qu'une plage d'ip du vnet en /16 et subnet en/24.
`az network vnet create -l eastus -g $NomDuGroupe -n $NomDuVnet --address-prefix $IpAddressVnet --subnet-name $NomDuSubnet --subnet-prefix $IpAddressSubnet`

* * *

## Créer une adresse IP publique

En amont de la création du load balancer nous créons une ip publique qui servira de frontend au load balancer.
`az network public-ip create -g $NomDuGroupe --name $NomIpPublic --sku Standard`

* * *

## Créer un équilibrage de charge

La mise en place du load balancer se fait en 3 parties:

### Creation de la ressource Load Balancer

`az network lb create -g $NomDuGroupe --name $NomDuLb --sku Standard --public-ip-address $NomIpPublic --frontend-ip-name $FrontendIpName --backend-pool-name $NomBackendPool`

### Création de la sonde d'intégrité

`az network lb probe create -g $NomDuGroupe --lb-name $NomDuLb -n $NomHealthProbe --protocol tcp --port 80`

### Régle du Load Balancer

`az network lb rule create --resource-group $NomDuGroupe --lb-name $NomDuLb --name $NomHTTPRule --protocol tcp --frontend-port 80 --backend-port 80 --frontend-ip-name $FrontendIpName --backend-pool-name $NomBackendPool --probe-name $NomHealthProbe --disable-outbound-snat true --idle-timeout 15 --enable-tcp-reset true`

* * *

## Groupe de sécurité réseau

### creaton du groupe de securité reseau

`az network nsg create --resource-group $NomDuGroupe --name $NomNSG`

### régle de securité port 80

`az network nsg rule create --resource-group $NomDuGroupe --nsg-name $NomNSG --name $NomNSGRuleHTTP --protocol '*' --direction inbound --source-address-prefix '*' --source-port-range '*' --destination-address-prefix '*' --destination-port-range 80 --access allow --priority 200`

### régle de securité port 22

`az network nsg rule create --resource-group $NomDuGroupe --nsg-name $NomNSG --name NSGRule22 --protocol '*' --direction inbound --source-address-prefix '*' --source-port-range '*' --destination-address-prefix '*' --destination-port-range 22 --access allow --priority 300`
*permettra l'accès ssh PAT*

* * *

## Création de VM Debian 11 et ajout au backend pool du load balancer

*nous nous servons d'une boucle bash pour la création de plusieurs vm qui permetra de générer des noms distincts pour les carte reseaux IP, vm, login et pass ainsi que zone (voir le script de création de ressource qui suit)*
Ce qui peut se faire via le menu creation de vm GUI, se fait en 3 étapes distincte en CLI:

### creation carte interface reseau vm

`az network nic create --resource-group $NomDuGroupe --name $compoNomNic --vnet-name $NomDuVnet --subnet $NomDuSubnet --network-security-group $NomNSG`

### creation de vm

`az vm create -g $NomDuGroupe -n $compoNomVm --admin-username $compoAdminName --admin-password $compoAdminPwd --image Debian:debian-11:11-gen2:0.20210928.779 --size Standard_D2_v4 --authentication-type password --private-ip-address $compoPrivateIp --zone $i --no-wait --nics $compoNomNic`

### ajout au backend pool du load balancer

`az network nic ip-config address-pool add --address-pool $NomBackendPool --ip-config-name ipconfig1 --nic-name $compoNomNic --resource-group $NomDuGroupe --lb-name $NomDuLb }`

* * *

## Créer une passerelle NAT

*Pour la connectivité sortante de nos vm nous créons une passerelle NAT que nous associons à notre subnet*

### IP publique NAT

`az network public-ip create --resource-group $NomDuGroupe --name myNATgatewayIP --sku Standard --zone 1 2 3`

### Création passerelle NAT

`az network nat gateway create --resource-group $NomDuGroupe --name $NomNatGateway --public-ip-addresses myNATgatewayIP --idle-timeout 10`

### Associer NAT au subnet

`az network vnet subnet update --resource-group $NomDuGroupe --vnet-name $NomDuVnet --name $NomDuSubnet --nat-gateway $NomNatGateway`

* * *

## Céation Azure Database MariaDB (saas)

### Creation de la ressource

`az mariadb server create --name $NomMariadb --resource-group $NomDuGroupe --location eastus --admin-user $NomAdminMDB --admin-password Adminpass1 --sku-name GP_Gen5_2 --version 10.3`

### Autorisation de l'ip sortante de nos vms dans le firewall de notre service MariaDB

- recuperation ip NAT et autorisation de l'ip dans la database
    `IPNATsortant=$(az network public-ip show --resource-group $NomDuGroupe --name myNATgatewayIP | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')`
- ajout de la régle pour cette ip dans le firewall mariadb
    `az mariadb server firewall-rule create --server-name $NomMariadb --resource-group $NomDuGroupe --name accesDBrule --end-ip-address $IPNATsortant --start-ip-address $IPNATsortant`

* * *

## Régle NAT/PAT pour accés vm en ssh

A ce stade notre réseau est crée mais nous ne pouvons pas nous connecter à nos vms.
Pour cela nous définissons des régles PAT dans l'inbound NAT rule du load balancer.
A défaut d'avoir les commandes pour le faire en cli nous le fesons en GUI.

- Dans le menu du load balancer cliquer sur Inbound **NAT** rules et **ADD**
    ![1.jpg](:/5df10c344e34425881e485415c535a1c)
    
- Ajouter une régle pour chaccune des vms sur un port distinct non utilisé
    ![2.jpg](:/47b541d98bd14906b6422c6b3083ec42)
    
- Nos régles apparaissent, chaque vm est accessible via l'ip front du load balancer via le port attribué en ssh.
    ![3.jpg](:/1076b96c2e194d309314e07d0f46893a)
    
- Exemple de commande de connexion ssh:
    `ssh Adminvm1@20.232.197.177 -p 33333`
    

* * *

## Installation de Apache et PHP sur Debian11

Nous allons procédé à l'installation des applicatifs
Dans un premier temps nous avions opté pour le confort d'utilisation de phpmyadmin pour la gestion des databases, mais pour le scripting sans intervention manuelles nous avons basculé sur l'instalation du module mariadb-client qui permet l'accès distant à la database et la finalisation du process d'instalation sans intervention manuelle.

- connexion en ssh à nos vms
- Update de la base de données de package
    `sudo apt -y update`
- Installation de php
    `sudo apt -y install php libapache2-mod-php php-mysql`
- Installation de Apache
    `sudo apt -y install apache2`
- Install maridb-client
    `sudo apt -y install mariadb-client`

* * *

## Installation de Wordpress sur les vms

- dans /var/www/html nous téléchargeons la derniere version de wordpress depuis le site officiel et le decompressons
    `sudo wget https://wordpress.org/latest.tar.gz sudo tar -xvf latest.tar.gz`
- copie du fichier config-sample
    `sudo cp wordpress/wp-config-sample.php wordpress/wp-config.php`
- attribution de la proprieté de wordpress à apache
    `sudo chown -R www-data:www-data /var/www/html/wordpress/`
- depuis /wordpress configuration de wordpress via les commandes sed, qui remplacent les valeurs par défaut liée a la database par les notres, afin de pouvoir connecter le futur site à notre saas mariadb.

```bash
sudo sed -i "s/database_name_here/$database_wp_name_here/" wp-config.php
sudo sed -i "s/username_here/$username_wp/" wp-config.php
sudo sed -i "s/password_here/$password_wp/" wp-config.php
sudo sed -i "s/localhost/$madatabase/" wp-config.php
```

- une fois la config faite, retrait des droit en écriture sur le fichier wp-config.php et restart de apache
    `sudo chmod u-w wp-config.php sudo systemctl restart apache2`
- connexion à la database distante
    `sudo mariadb --user=$username --password=$password_here --host=$madatabase`
- creation de la base de donnée wordpress
    `CREATE DATABASE IF NOT EXISTS $database_wp_name_here default character set utf8 collate utf8_unicode_ci;`
    A ce stade si les memes login que ceux du saas mariadb sont utilisés le site wordpress peut déjà être installé en gui. Il suifft de lancer un navigateur avec l'ip publique front du loadbalancer /wordpress.

* * *

## Installation de wordpress

L'installation est intuitive, nous sommes guidés pas à pas en gui,

- nom du site
- login
- email admin
- et premiere connexion sur le tableau de bord
- notre site est configurable en interface What I See Is What I Get.

* * *

## Azure Monitor

- Chercher application insights puis cliquer sur **Create**
    ![Screenshot_2.jpg](:/20b0590fd2e543bdbca63a4ce5358732)
- Entrer information liée au ressoruce groupe à monitorer
    ![Screenshot_1.jpg](:/46e305b948be4ad2abaf96cc4c369da0)
- Prendre note de l'instrumentation key généree qui sera demandé dans wordpress pour faire lien.
    ![Screenshot_3.jpg](:/51a57b2104a347cf9ef7649184c5fe18)
- Dans wordpress > Plugins > ajouter nouveau
    ![Screenshot_4.jpg](:/e8c2c51af49c4f42b69f3a169b8321d8)
- Rechercher Application insights et installer le plugin
    ![Screenshot_5.jpg](:/5814711d27ff46089a2db4568feb8895)
- Puis cliquer activer now
    ![Screenshot_6.jpg](:/bff69a7a019b42e4ad64483d3819535b)
- Pour fournir l'instrumentation key de l'application insight d'azure.
    ![Screenshot_7.jpg](:/f07ec04b5d9a4764a0f82a394cf3ec0f)
- Notre azure monitor est fonctionnel
    ![Screenshot_8.jpg](:/a809971bcb31402fb54ddf9be495de68)

* * *

## Test wordpress Load Balancé

## En arretant une vm sur deux, nous voyons que le site est toujours disponible, en changeat de vm arrétée, il en est de même. Notre site est bien load balancé.

![test3.jpg](:/e377fcdacf924717918712e0c9af871e)

![gifvm2.gif](:/8936143c125b4b83b76a5e78af315c28)

![gifvm1.gif](:/3bc0c9a5abb84bcaa59c963c5771947a)

* * *

## Script de création ressources Azure

```bash
#!/bin/bash
echo "########################################################################
#  Script Creation de ressources Azure                                 #
#  version 1 : Jeremy                                                  #
#  version 2 : Jeremy (data structure : fonction)                      #
#  version 3 : Alain (modif create_vm en nsg nic vm be)                #
#  version 3.1 : Alain (ajout menu, regle firewall db ip nat)          #
########################################################################"

# echo "Nom du groupe"
# read NomDuGroupe
# echo "Nom du Vnet"
# read NomDuVnet
# echo "ip address vnet"
# read IpAddressVnet
# echo "Nom du subnet"
# read NomDuSubnet
# echo "ip address subnet"
# read IpAddressSubnet
# echo "Nom ip public"
# read NomIpPublic
# echo "Nom du load balancer"
# read NomDuLb
# echo "Backend pool name"
# read NomBackendPool
# echo "Nom de l'address backend"
# read NomIpBackend
# echo "ip address du pool backend"
# read IpAddressBackend
# echo "Nom du health probe"
# read NomHealthProbe
# echo "Nom de la vm"
# read NomVm
# echo "Admin user name"
# read AdminName
# echo "Admin password"
# read AdminPwd
# echo "Private Ip Address"
# read PrivateIp
# echo "Frontend Ip name"
# read FrontendIpName
# echo "HTTP Rule"
# read NomHTTPRule
# echo "Network Security Group"
# read NomNSG
# echo "Network Security Group Rule"
# read NomNSGRuleHTTP
# echo "Network Interface Card"
# read NomNic
# echo "NAT Gateway name"
# read NomNatGateway

#########################################
NomDuGroupe=G1_B5-v3
NomDuVnet=nomvnet
IpAddressVnet=10.0.0.0/16
NomDuSubnet=nomsubnet
IpAddressSubnet=10.0.0.0/24
NomIpPublic=monIPPublic
NomDuLb=monLBB
NomBackendPool=monBackendPool
NomIpBackend=monIPbackend
IpAddressBackend=ipadressBack
NomHealthProbe=monHP
NomVm=maVM
AdminName=adminvm
AdminPwd=Adminvmpass
PrivateIp=10.0.0.5
FrontendIpName=monIPfront
NomHTTPRule=moHTTPrule
NomNSG=monNSG
NomNSGRuleHTTP=monNSGruleHTTP
NomNic=monNic
NomNatGateway=monNATgate
NomMariadb=mdbg1b5database
NomAdminMDB=mdbg1admin1
nbzone=3

###########################################
#ressource group
Create_groupe(){
echo "Nom du groupe"
read NomDuGroupe
az group create --location eastus --name $NomDuGroupe
echo -e "${VERT}Groupe de ressource $NomDuGroupe crée !!${NC}"
}

Appel_groupe(){
echo "Nom du groupe ressource"
read NomDuGroupe
}
#########################################
#azure database mariadb saas
Create_mariadb(){

az mariadb server create --name $NomMariadb --resource-group $NomDuGroupe --location eastus --admin-user $NomAdminMDB --admin-password Adminpass1 --sku-name GP_Gen5_2 --version 10.3 --ssl-enforcement Disabled
###########ouverture port mariadb saas pour vm NAT
#recuperation ip NAT et autorisation de l'ip dans la database
IPNATsortant=$(az network public-ip show --resource-group $NomDuGroupe --name myNATgatewayIP | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
az mariadb server firewall-rule create --server-name $NomMariadb  --resource-group $NomDuGroupe --name accesDBrule --end-ip-address $IPNATsortant --start-ip-address $IPNATsortant

echo -e "${VERT}Database Azure mariaDB crée  !! ${NC}"

echo "nom hote database azure mariadb "$NomMariadb
echo "nom admin mariadb "$NomAdminMDB
echo "mot de passe admin mariadb Adminpass1"
}
################################################################
#vnet
Create_vnet(){

 az network vnet create -l eastus -g $NomDuGroupe -n $NomDuVnet --address-prefix $IpAddressVnet --subnet-name $NomDuSubnet --subnet-prefix $IpAddressSubnet
 
 echo -e "${VERT}Virtual Network crée !!${NC}"
}
#################################################################

##################################################################
# Load balancer :
#     -Ip publique
#     -ressource lb
#     -sonde integrité
#     -règle load balancer
Create_load_balancer(){
    #Ip publique
 az network public-ip create -g $NomDuGroupe --name $NomIpPublic --sku Standard
    #ressource LB
 az network lb create -g $NomDuGroupe --name $NomDuLb --sku Standard --public-ip-address $NomIpPublic --frontend-ip-name $FrontendIpName --backend-pool-name $NomBackendPool
    #sonde integrité
 az network lb probe create -g $NomDuGroupe --lb-name $NomDuLb -n $NomHealthProbe --protocol tcp --port 80
    #règle du LB
az network lb rule create --resource-group $NomDuGroupe --lb-name $NomDuLb --name $NomHTTPRule --protocol tcp --frontend-port 80 --backend-port 80 --frontend-ip-name $FrontendIpName --backend-pool-name $NomBackendPool --probe-name $NomHealthProbe --disable-outbound-snat true --idle-timeout 15 --enable-tcp-reset true

echo -e "${VERT}LoadBalancer crée  !!${NC}"
}


####################################################################
#creation groupe de securité reseau
#regle de groupe de securité reseau
Create_nsg(){
    #creation groupe
    az network nsg create --resource-group $NomDuGroupe --name $NomNSG
    #regle de securité1
    az network nsg rule create --resource-group $NomDuGroupe --nsg-name $NomNSG --name $NomNSGRuleHTTP --protocol '*' --direction inbound --source-address-prefix '*' --source-port-range '*' --destination-address-prefix '*' --destination-port-range 80 --access allow --priority 200
    #regle de securité2
    az network nsg rule create --resource-group $NomDuGroupe --nsg-name $NomNSG --name NSGRule22 --protocol '*' --direction inbound --source-address-prefix '*' --source-port-range '*' --destination-address-prefix '*' --destination-port-range 22 --access allow --priority 300

echo -e "${VERT}Network Security Groupe crée  !!${NC}"
}
##############################################################

##############################################################
# creation vm , interface reseau, ajout au pool backend LB    
    #creation interfaces reseau vm
Create_nic(){
az network nic create --resource-group $NomDuGroupe --name $compoNomNic --vnet-name $NomDuVnet --subnet $NomDuSubnet --network-security-group $NomNSG
}
    #creation des vms
Create_vm(){
 az vm create -g $NomDuGroupe -n $compoNomVm --admin-username $compoAdminName --admin-password $compoAdminPwd --image Debian:debian-11:11-gen2:0.20210928.779 --size Standard_D2_v4 --authentication-type password --private-ip-address $compoPrivateIp --zone $numZone --no-wait --nics $compoNomNic
#ouverture port
#commande qui semble inutile avec le nsg, ou a modifier
#  az vm open-port -g $NomDuGroupe -n $compoNomVm --port 80
#  az vm open-port -g $NomDuGroupe -n $compoNomVm --port 22
}
    #ajout de vm au pool backend du load balancer
Ajout_BE_Pool(){
az network nic ip-config address-pool add --address-pool $NomBackendPool --ip-config-name ipconfig1 --nic-name $compoNomNic --resource-group $NomDuGroupe --lb-name $NomDuLb    
}
#################################################################

################################################################
#passerelle NAT
    #IP publique pour connectivité sortante
    #creation ressource Passerelle NAT
    #associer NAT au subnet
Create_NAT(){
#IP publique
az network public-ip create --resource-group $NomDuGroupe --name myNATgatewayIP --sku Standard --zone 1 2 3
#ressource Passerelle NAT
az network nat gateway create --resource-group $NomDuGroupe --name $NomNatGateway --public-ip-addresses myNATgatewayIP --idle-timeout 10
#associer NAT au subnet
az network vnet subnet update --resource-group $NomDuGroupe --vnet-name $NomDuVnet --name $NomDuSubnet --nat-gateway $NomNatGateway

echo -e "${VERT}NAT gateway crée  !!${NC}"
}

CreateVMplus(){
    Create_nsg
    i=1
    while [ $i -le $NombreVm ]
    do
    compoNomVm=$NomVm$i
    compoAdminName=$AdminName$i
    compoAdminPwd=$AdminPwd$i
    compoPrivateIp=$PrivateIp$i
    compoNomNic=$NomNic$i
    #distribution des vms par zone
    numZone=$(($i%$nbzone+1))
    echo "Create vm"
    Create_nic
    Create_vm
    Ajout_BE_Pool
    i=$((i+1))
    done

    echo -e "${VERT}Les Virtual Machines ont été crées  !!${NC}"
}

###################################################################

###################################################################

##############################################################
# menu choix
menu(){
#regular expression re, ensemble nombre de 0 à 9
re='^[0-9]+$'
#un peu de couleur bonus
RED='\033[0;31m'
VERT='\033[1;32m'
NC='\033[0m' # No Color
while
echo "########################################################"
echo "########  Menu de creation de ressource Azure  #########"
echo "#  1: Ressource group                                  #"
echo "#  2: Vnet                                             #"
echo "#  3: LoadBalancer                                     #"
echo "#  4: VM avec (NSG, NIC, Ajout au BackendPool du LB)   #"
echo "#  5: NAT                                              #"
echo "#  6: Azure Mariadb Database (saas)                    #"
echo "#  7: Infra entiere (2vms loadbalancées + Mariadb(saas)#"
echo "#  8: Quitter le menu                                  #"
echo "########################################################"
echo "Entrer le numéro associé à votre séléction"
echo "Votre choix"
read choix

do
    if  [[ $choix =~ $re ]] #check si le choix est un nombre avec le regex $re
        then
            case $choix in
                1) echo "Create ressource group"
                    Create_groupe;;
                2) echo "Create vnet"
                    Appel_groupe
                    Create_vnet;;
                3) echo "Create load balancer"
                    Appel_groupe
                    Create_load_balancer;;
                4) echo "Vm Number"
                    Appel_groupe
                    read NombreVm
                    if (( $NombreVm -le 3))
                    then
                        CreateVMplus
                    else
                        echo "Pour les besoins du test veuillez entrer un nombre inferieur ou egal à 3"
                        exit 1
                    fi;;
                5) echo "Creating NAT Gateway"
                        Appel_groupe
                        Create_NAT;;
                6) echo "Creating Azure Mariadb saas"
                        Appel_groupe
                        Create_mariadb;;
                7) echo " Creation de l'infrastructure entiere pour 2vms et variables preset" 
                        Create_groupe
                        NombreVm=2
                        Create_vnet
                        Create_load_balancer
                        CreateVMplus
                        Create_NAT
                        Create_mariadb;;
                8) echo "A bientôt"; exit 1;;
                *) echo -e "${RED}Erreur: choix non valide, entrez numéro de choix existant${NC}";;
            esac
        else
        echo -e "${RED}Erreur: choix non valide, veuillez entrer un nombre${NC}" ;
    fi
done
}

menu
```

* * *

## Script d'installation Lamp Wordpress

```bash
#!/bin/bash
echo "########################################################################
#  Script Installation apache php wordpress                            #
#  version 1 : Alain                                                   #
#  version 2 : Alain (remplacement de phpmyadmin par mariadb-client)   #
#  version 3 : Saïf, Amine (ajout commande sed)                        #
#  version 4 : Alain (ajout connexion mariadb, script sql)             #
########################################################################"

# Récupération des infos database et futur login wordpress
echo "nom hote database"
read madatabase
echo "nom utilisateur azure maria db"
read username
echo "Si vous voulez un utilisateur wp db dédié different entrez le à la suite sinon laisser vide et taper entré"
read username_wp
echo "password utilisateur azure maria db"
read password_here
echo "Si vous voulez un pass wp db different entrez le à la suite sinon laisser vide et taper entré"
read password_wp
echo "nom de base de donnée wp"
read database_wp_name_here

#check si login et pass azure db et wp db different
if [[ -z ${username_wp} ]]
then
    username_wp=$username
fi

if [[ -z ${password_wp} ]]
then
    password_wp=$password_here
    echo "pass vide"
fi


sudo apt -y update
# Installation de php
sudo apt -y install php libapache2-mod-php php-mysql
# Installation de Apache
sudo apt -y install apache2
# Install maridb-client
sudo apt -y install mariadb-client


#####################################################################
#                            WORDPRESS                              #
#####################################################################
cd /var/www/html/

sudo wget https://wordpress.org/latest.tar.gz

sudo tar -xvf latest.tar.gz


sudo cp wordpress/wp-config-sample.php wordpress/wp-config.php
sudo chown -R www-data:www-data /var/www/html/wordpress/
cd wordpress/
####################################################
#          config wordpress                        #
####################################################

sudo sed -i "s/database_name_here/$database_wp_name_here/" wp-config.php
sudo sed -i "s/username_here/$username_wp/" wp-config.php
sudo sed -i "s/password_here/$password_wp/" wp-config.php
sudo sed -i "s/localhost/$madatabase/" wp-config.php

sudo chmod u-w wp-config.php

sudo systemctl restart apache2

###config mariadb saas de wordpress

#creation fichier instruction sql 
sudo echo "CREATE DATABASE IF NOT EXISTS $database_wp_name_here default character set utf8 collate utf8_unicode_ci;
# CREATE USER IF NOT EXISTS '$username_wp'@'$database_wp_name_here' IDENTIFIED BY '$password_wp';
# GRANT ALL on $database_wp_name_here.* to '$username_wp'@'$database_wp_name_here' identified by '$password_wp';
# flush privileges;
" > instructionsql.sql

#connexion mariadb-client avec password et injection de nos instruction liée a wordpress
sudo mariadb --user=$username --password=$password_here --host=$madatabase < instructionsql.sql > output.tab

# sudo mariadb --user=mdbg1admin1 --password=Adminpass1 --host=mdbg1b5database.mariadb.database.azure.com < instructionsql.sql > output.tab
# creation de wordpressdb et utilisateur si elle n'existe pas
# CREATE DATABASE IF NOT EXISTS $database_wp_name_here default character set utf8 collate utf8_unicode_ci;
# CREATE USER IF NOT EXISTS '$username_wp'@'$database_wp_name_here' IDENTIFIED BY '$password_wp';
# GRANT ALL on $database_wp_name_here.* to '$username_wp'@'$database_wp_name_here' identified by '$password_wp';
# flush privileges;
# exit;





########################################################
# wordpress config pour apache                          #
########################################################
#il semblerait que le vhost ne soit pas obligatoire, on fait sans pour l'instant
# cd /etc/apache2/sites-available/

# sudo echo '<VirualHost *:80>
#     ServerAdmin webmaster@localhost
#     DocumentRoot /var/www/html/wordpress

#     EerroLog ${APACHE_LOG_DIR}/error.log
#     CustomLog ${APACHE_LOG_DIR}/access.log combined
# </VirtualHost>' > /etc/apache2/sites-available/000-default.conf
```

* * *

## Problèmes rencontrés

- Vms non accessibles individuelement : utilisation de Bastion ou PAT voir section **Régle NAT/PAT pour accés vm en ssh** .
- Probleme reglé avec regle de creation inbound nat rule du lb
```bash
Create_InboundNat(){
### regle pour inbound nat port 22 pour la connexion en ssh sur chaque vm
az network lb inbound-nat-rule create --backend-port 22 --resource-group $NomDuGroupe --lb-name NomDuLb --name PATvm1 --backend-pool-name $NomBackendPool --protocol Tcp --frontend-ip-name $FrontendIpName --frontend-port-range-start 33333 --frontend-port-range-end 33334
### regle pour inbound nat port 80 pour voir l'impact des changements via navigateur sur chaque vm separée sans avoir à en arreter une
az network lb inbound-nat-rule create --backend-port 80 --resource-group $NomDuGroupe --lb-name NomDuLb --name PATvm80 --backend-pool-name $NomBackendPool --protocol Tcp --frontend-ip-name $FrontendIpName --frontend-port-range-start 44444 --frontend-port-range-end 44445
}
```

### Amelioration
- transfert script en scp
https://linuxize.com/post/how-to-use-scp-command-to-securely-transfer-files/