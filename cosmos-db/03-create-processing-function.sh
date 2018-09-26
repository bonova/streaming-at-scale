#!/bin/bash

PLAN_NAME=$PROC_FUNCTION_APP_NAME"plan"

echo 'creating app service plan'
echo ". name: $PLAN_NAME"
az appservice plan create -g $RESOURCE_GROUP -n $PLAN_NAME \
--number-of-workers $PROC_FUNCTION_WORKERS --sku P1 --location $LOCATION \
-o tsv >> log.txt

echo 'creating function app'
echo ". name: $PROC_FUNCTION_APP_NAME"
az functionapp create -g $RESOURCE_GROUP -n $PROC_FUNCTION_APP_NAME \
--plan $PLAN_NAME \
--storage-account $AZURE_STORAGE_ACCOUNT \
-o tsv >> log.txt

echo 'creating zip file'
CURDIR=$PWD
rm $PROC_PACKAGE_PATH
cd $PROC_PACKAGE_FOLDER/$PROC_FUNCTION_NAME-$PROC_PACKAGE_TARGET/$PROC_FUNCTION_NAME-$PROC_PACKAGE_TARGET/bin/Release/net461/
for TEST_ID in {0..9}
do
    if [ -f ./Test$TEST_ID/function.json ]; then
        # disable all functions
        sed -i -e 's/"disabled": false/"disabled": true/g' ./Test$TEST_ID/function.json
    fi    
done
# enable only the function specified in host.json
ACTIVE_TEST=`grep "functions" host.json | awk '{ print $3 }' | sed 's/"//g'`
echo " .enabling function: $ACTIVE_TEST"
sed -i -e 's/"disabled": true/"disabled": false/g' ./$ACTIVE_TEST/function.json
zip -r $CURDIR/$PROC_PACKAGE_FOLDER/$PROC_PACKAGE_NAME . 
cd $CURDIR

echo 'configuring function app deployment source'
echo ". src: $PROC_PACKAGE_PATH"
az functionapp deployment source config-zip \
--resource-group $RESOURCE_GROUP \
--name $PROC_FUNCTION_APP_NAME  --src $PROC_PACKAGE_PATH \
-o tsv >> log.txt

echo 'getting shared access key'
EVENTHUB_CS=`az eventhubs namespace authorization-rule keys list -g $RESOURCE_GROUP --namespace-name $EVENTHUB_NAMESPACE --name RootManageSharedAccessKey --query "primaryConnectionString" -o tsv`

echo 'adding app settings for connection strings'

echo ". EventHubsConnectionString: $EVENTHUB_CS"
az functionapp config appsettings set --name $PROC_FUNCTION_APP_NAME \
--resource-group $RESOURCE_GROUP \
--settings EventHubsConnectionString=$EVENTHUB_CS \
-o tsv >> log.txt

echo ". EventHubPath: $EVENTHUB_NAME"
az functionapp config appsettings set --name $PROC_FUNCTION_APP_NAME \
--resource-group $RESOURCE_GROUP \
--settings EventHubName=$EVENTHUB_NAME \
-o tsv >> log.txt

echo ". ConsumerGroup: $EVENTHUB_CG"
az functionapp config appsettings set --name $PROC_FUNCTION_APP_NAME \
--resource-group $RESOURCE_GROUP \
--settings ConsumerGroup=$EVENTHUB_CG \
-o tsv >> log.txt

echo 'creating AppInsights'
az resource create --resource-group $RESOURCE_GROUP --resource-type "Microsoft.Insights/components" \
--name $PROC_FUNCTION_APP_NAME-appinsights --location $LOCATION --properties '{"ApplicationId":"StreamingAtScale","Application_Type":"other","Flow_Type":"Redfield"}' \
-o tsv >> log.txt

echo 'getting AppInsights instrumentation key'
APPINSIGHTS_INSTRUMENTATIONKEY=`az resource show -g $RESOURCE_GROUP -n $PROC_FUNCTION_APP_NAME-appinsights --resource-type "Microsoft.Insights/components" --query properties.InstrumentationKey -o tsv`

echo 'configuring azure function with AppInsights'
echo ". APPINSIGHTS_INSTRUMENTATIONKEY: $APPINSIGHTS_INSTRUMENTATIONKEY"
az functionapp config appsettings set --name $PROC_FUNCTION_APP_NAME \
--resource-group $RESOURCE_GROUP \
--settings APPINSIGHTS_INSTRUMENTATIONKEY=$APPINSIGHTS_INSTRUMENTATIONKEY \
-o tsv >> log.txt