## Brief10 : Docker + Azure = love
## Script Done by : Yvette , Driton, Alain

###########################################################
## Script For Web APP Wordpress - autoscaled - + MariaDB ##
###########################################################

#variable preset
group=Groupe5_Brief10_YDA
location=westeurope
appserviceplanname=g5b10ydaasp
webappname=Groupe5_Brief10_YDA
username=Admin1
password=Adminpass1

###########################################################
##Resource group
createRG(){
    echo " creating ressource groupe "
    az group create -n $group -l $location
}

############################################################
## create webapp adqsdq dqdq 
createApp(){
    echo " creating app plan "
    az appservice plan create -g $group  -n $appserviceplanname --is-linux --number-of-workers 4 --sku P1V2
    echo " creating Web app "
    az webapp create --resource-group $group --plan $appserviceplanname --name $webappname --deployment-container-image-name alaincloud/mediawiki:stable
    echo " creating slots"
    # reste à faire
    az webapp deployment slot create --name $webappname --resource-group $group --slot DEV --deployment-container-image-name -i alaincloud/mediawiki:dev3

    #echo " modif WP-config "
    #az webapp config appsettings set -n alainb8wap -g $group --settings MARIA_DB_HOST="alainb8-mdb.mariadb.database.azure.com" MARIA_DB_USER="$username"  MARIA_DB_PASSWORD="$password"  WEBSITES_ENABLE_APP_SERVICE_STORAGE=TRUE
}

############################################################
#tout creer
createAll(){
    createRG
    createApp
}

createAll
echo "installation terminée"