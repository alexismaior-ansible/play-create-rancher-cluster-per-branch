#!/bin/bash

helpFunction()
{
   echo "Script que cria um ambiente do siop em um namespace do cluster dev-test a partir de uma cópia de staging do cluster production"
   echo ""
   echo "PASSO-A-PASSO PARA EXECUÇÃO: "
   echo "  1. Instalar o cli do 'helm v3' (https://get.helm.sh/helm-v3.2.3-linux-amd64.tar.gz)"
   echo "  2. Instalar o cli do 'kubectl' (https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-on-linux)"
   echo "  3. Adicionar o repositorio do harbor localmente
                        helm repo add harbor https://harbor.app.sof.intra/chartrepo --username XXXXXX --password XXXXXX"
   echo "  4. Criar no RANCHER o seu namespace (que tera a copia do staging) no cluster dev-test."
   echo ""
   echo "IMPORTANTE:"
   echo "  Na primeira execução, rode com o parâmetro '-f true' para que TODOS OS OBJETOS sejam importados 1 vez."
   echo ""
   echo "Uso: $0 -n namespace -p /path/to/kubeconfig  -t  /path/to/kubeconfig -r repositorio -f false "
   echo -e "\t-n Namespace a ser criado"
   echo -e "\t-p Caminho do arquivo do kubeconfig do ambiente production. Faça o download do mesmo pelo Rancher."
   echo -e "\t-t Caminho do arquivo do kubeconfig do ambiente dev-test. Faça o download do mesmo pelo Rancher."
   echo -e "\t-r Nome do repositorio criado localmente (Ex: harbor)"
   echo -e "\t-i URL a ser setada como ingress (Ex: dev-xxx.test.app.sof.intra)"
   echo -e "\t-c Caminho do arquivo do Certificado do repositorio (Ex: casof.crt)"
   echo -e "\t-f (Opcional) true/false. Forca a delecao de todos os objetos do namespace e a criacao de um novo.
                            Por padrão, apenas o update da versão dos servicos será feito, atraves do 'helm update'"
   exit 1 # Exit script after printing help
}

while getopts "n:p:t:r:i:c:f:" opt
do
   case "$opt" in
      n ) namespace="${OPTARG}" ;;
      p ) kubeconfig_prod="$OPTARG" ;;
      t ) kubeconfig_devtest="$OPTARG" ;;
      r ) repo="$OPTARG" ;;
      i ) ingress="$OPTARG" ;;
      c ) cafile="$OPTARG" ;;
      f ) force="true" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$namespace" ] || [ -z "$kubeconfig_prod" ] || [ -z "$kubeconfig_devtest" ] || [ -z "$repo" ]
then
	echo "ERRO: Algum(s) parametros estao vazios";
	echo "";
   helpFunction
fi

# Checa se o namespace realmente existe
kubectl --kubeconfig=$kubeconfig_devtest  get ns $namespace &> /dev/null
if [ $? -eq 1 ]; then  echo "Namespace $namespace não existe. Criando..."
    kubectl --kubeconfig=$kubeconfig_devtest create ns $namespace &> /dev/null
fi

if [ "$force" == "true" ];
then
        echo "Exculindo objetos do namespace $namespace";
	kubectl delete deploy,ds,pods,sa,services,ingress,cm,secrets --all --kubeconfig=$kubeconfig_devtest -n $namespace  &> /dev/null
fi

#exporta os configmaps de staging e importa no ambiente de teste
if [ "$force" == "true" ];
then
    for n in $(kubectl --kubeconfig=$kubeconfig_prod get configmap -n staging  -o custom-columns=:metadata.name --no-headers)
        do
          echo "instalando o configmap $n do staging no namespace $namespace"
          kubectl --kubeconfig=$kubeconfig_prod get configmap $n -n staging --export -o yaml | kubectl --kubeconfig=$kubeconfig_devtest apply --namespace=$namespace -f-  &> /dev/null
    done
fi

#exporta os secrets de staging e importa no ambiente de teste
if [ "$force" == "true" ];
then
    for n in $(kubectl --kubeconfig=$kubeconfig_prod get secrets -n staging --field-selector=type!=kubernetes.io/service-account-token -o custom-columns=:metadata.name --no-headers)
       do
          echo "instalando os secrets $n do staging no namespace $namespace"
          kubectl --kubeconfig=$kubeconfig_prod get secret $n -n staging --export -o yaml | kubectl --kubeconfig=$kubeconfig_devtest apply --namespace=$namespace -f-  &> /dev/null
    done
fi

#Instala todos os charts das aplicacoes de producao no novo namespace de teste
helm repo update  &> /dev/null

for n in $(kubectl --kubeconfig=$kubeconfig_prod get deploy -n production -o custom-columns=:metadata.name --no-headers)
   do
      echo "instalando o chart $n no namespace $namespace"
      helm upgrade --kubeconfig=$kubeconfig_devtest --install $n $repo/siop/$n --namespace=$namespace --set ingress.host=$ingress --ca-file $cafile  &> /dev/null
      echo "URL do ingress setada para $namespace.test.app.sof.intra"
done
