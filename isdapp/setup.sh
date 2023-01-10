#!/bin/bash
appname=$1 # a folder an application and a namespace will be created using this
appns=$2 # baseline namespace
isdurl=$3 # preview namespace


usage='error: Usage: ./setup.sh APP-NAME APP-NS ISD_URL'

if [ -z $appname ]; then echo $usage; exit 1; fi
if [ -z $appns ]; then  echo $usage; exit 1; fi
if [ -z $isdurl ]; then  echo $usage; exit 1; fi

#replace APP-NAME APP-NS ISD-URL
sed -i "s/APP-NAME/$appname/g" analysistemplate.tmpl
sed -i "s/APP-NAME/$appname/g" configmap.tmpl
sed -i "s/APP-NS/$appns/g" configmap.tmpl
sed -i "s#ISD-URL#$isdurl#g" configmap.tmpl
sed -i "s#ISD-URL#$isdurl#g" opsmx-profile-secret.tmpl
sed -i "s/APP-NAME/$appname/g" sa-role-rb.tmpl
sed -i "s/APP-NS/$appns/g" sa-role-rb.tmpl

find . -type f  -name "*ml"  > allyamls.txt

while read yamlfile
do
echo checking file $yamlfile
if [ $(yq -r '.kind' $yamlfile )  == Deployment ]
then
echo $yamlfile is a deployment yaml
echo
echo changing replicas to zero in $yamlfile 
yq -i -r '.spec.replicas = 0' $yamlfile
echo number of replicas in $yamlfile $(yq -r '.spec.replicas' $yamlfile)
echo
deployname=$(yq -r '.metadata.name' $yamlfile)
echo creating rollout for this deployment $deployname
cp rollout.tmpl "$deployname"-rollout.yaml
sed -i "s/DEPLOY-NAME/$deployname/g" "$deployname"-rollout.yaml
echo $yamlfile >>deploys.txt
echo creating analysis template for this deployment $deployname
cp analysistemplate.tmpl "$deployname"-at.yaml
labelappname=$(yq -r '.spec.selector.matchLabels.app' $yamlfile)
sed -i "s/DEPLOY-NAME/$deployname/g" "$deployname"-at.yaml
sed -i "s/DEPLOY-LABEL/$labelappname/g" "$deployname"-at.yaml
fi


if [ $(yq -r '.kind' $yamlfile )  == Service ]
then
echo $yamlfile is a service yaml
if echo $yamlfile | grep -v stable | grep -v preview
then
     echo $yamlfile >>services.txt
fi
fi
done < allyamls.txt

echo
echo
echo

while read deploy
do
yq -r '.spec.selector.matchLabels' $deploy > temp-deploy.txt
cat temp-deploy.txt
deployname=$(yq -r '.metadata.name' $deploy)

    while read service
    do
    yq -r '.spec.selector' $service > temp-service.txt
    cat temp-service.txt
    diff temp-deploy.txt temp-service.txt
    if [ $? == 0 ]
    then 
    echo $service corresponds to $deploy
    servicename=$(yq -r '.metadata.name' $service)
    sed -i "s/SERVICE-NAME/$servicename/g" "$deployname"-rollout.yaml
         while read line 
          do echo $line is used for selector;
          key=$(echo $line | awk '{print $1}'| sed 's/://')
          echo $key is the key
          value=$(echo $line | awk '{print $2}')
          value='"'$value'"'
          echo $value is the value
          cmd="yq -i '.spec.selector.matchLabels.${key} = ${value}' "$deployname"-rollout.yaml"
          eval $cmd
          done < temp-service.txt
    break
    fi
    done < services.txt
done < deploys.txt

    while read service
    do
    echo creating preview and stable services
        servicename=$(yq -r '.metadata.name' $service)
    cp $service "$servicename"-stable.yaml
    stablename="$servicename"-stable
    stablename='"'$stablename'"'
    cmd="yq -i '.metadata.name = ${stablename}' "$servicename"-stable.yaml"
              eval $cmd
    cp $service "$servicename"-preview.yaml
    previewname="$servicename"-preview
    previewname='"'$previewname'"'
    cmd="yq -i '.metadata.name = ${previewname}' "$servicename"-preview.yaml"
              eval $cmd
    
    done < services.txt


echo creating metric template , sa, role, rolebinding, secret
cp metrixtemplate.tmpl metrixtemplate.yaml
cp sa-role-rb.tmpl sayaml-role-rb.yaml
cp opsmx-profile-secret.tmpl opsmx-profile-secret.yaml

metrictemplatename=$(cat metrixtemplate.yaml | yq -r '.data' | head -n 1 | awk '{print $1}' | sed 's/://')

echo creating configmaps
while read deploy
do
deploylabel=$(yq -r '.spec.selector.matchLabels.app' $deploy)
deployname=$(yq -r '.metadata.name' $deploy)
cp configmap.tmpl $deployname-configmap.yaml
sed -i "s/DEPLOY-NAME/$deployname/g" $deployname-configmap.yaml
sed -i "s/DEPLOY-LABEL/$deploylabel/g" $deployname-configmap.yaml
sed -i "s/metrixtemplates/$metrictemplatename/g" $deployname-configmap.yaml
done < deploys.txt



rm -rf allyamls.txt deploys.txt services.txt temp-deploy.txt temp-service.txt
