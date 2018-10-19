
#!/bin/bash

. /etc/sysconfig/heat-params

if [ "$(echo $ENDPOINT | tr '[:upper:]' '[:lower:]')" = "false" ]; then
    exit 0
fi

if [ "$VERIFY_CA" == "True" ]; then
    VERIFY_CA=""
else
    VERIFY_CA="-k"
fi

auth_json=$(cat << EOF
{
    "auth": {
        "identity": {
            "methods": [
                "password"
            ],
            "password": {
                "user": {
                    "id": "$TRUSTEE_USER_ID",
                    "password": "$TRUSTEE_PASSWORD"
                }
            }
        }
    }
}
EOF
)

user_data_script='''#!/bin/sh
content_type="Content-Type: application/json"
url="'''${AUTH_URL}'''/auth/tokens"

CERT_DIRECTORY=/srv/$REGION_NAME
mkdir -p "$CERT_DIRECTORY"

cat > $CERT_DIRECTORY/server.conf <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no
[req_distinguished_name]
CN = admin
O = system:masters
EOF

_CA_CERT=$CERT_DIRECTORY/ca.pem
_CERT=$CERT_DIRECTORY/cert.pem
_KEY=$CERT_DIRECTORY/key.pem
_CSR=$CERT_DIRECTORY/csr.pem
_CONF=$CERT_DIRECTORY/server.conf

USER_TOKEN=`curl '''${VERIFY_CA}''' -s -i -X POST -H "$content_type" -d "'''${auth_json}'''" $url \
    | grep -i X-Subject-Token | awk "{print $2}" | tr -d "[[:space:]]"`

# Get CA certificate for this cluster
curl $VERIFY_CA -X GET \
    -H "X-Auth-Token: $USER_TOKEN" \
    -H "OpenStack-API-Version: container-infra latest" \
    '''${MAGNUM_URL}'''/certificates/'''${CLUSTER_UUID}''' | python -c "import sys, json; print json.load(sys.stdin)[\"pem\"]" > $_CA_CERT

# Generate private key and csr
openssl req -newkey rsa:2048 
        -new -nodes \
        -x509
        -days 1000
        -keyout "$_KEY"
        -out "$_CSR"
        -config "$_CONF"

cert_json=$(cat << EOF
{
    "cluster_uuid": "'''${CLUSTER_UUID}'''"
    "csr": "$(cat $_CSR)"
}
EOF
)

# Generate cert
curl $VERIFY_CA -X POST \
    -H "X-Auth-Token: $USER_TOKEN" \
    -H "OpenStack-API-Version: container-infra latest" \
    -H "$content_type"
    -d "$cert_json"
    '''${MAGNUM_URL}'''/certificates | python -c "import sys, json; print json.load(sys.stdin)[\"pem\"]" > $_CERT

# Generate kube config
kube_config_file=/home/ubuntu/.kube/config
kube_config_content=$(cat << EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority: $_CA_CERT
    server: https://$KUBE_API_PUBLIC_ADDRESS:$KUBE_API_PORT
  name: $CLUSTER_UUID
contexts:
- context:
    cluster: $CLUSTER_UUID
    user: admin
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: admin
  user:
    client-certificate: $_CERT
    client-key: $_KEY
EOF
)

mkdir -p $(dirname $kube_config_file)
cat << EOF > ${kube_config_file}
$kube_config_content
EOF

sudo apt-get update && sudo apt-get install -y apt-transport-https
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo touch /etc/apt/sources.list.d/kubernetes.list 
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl
'''

user_data=$(echo $user_data_script | base64)

instance_json=$(cat << EOF
{
    "server" : {
        "name" : "endpoint-$REGION_NAME",
        "imageRef" : "80dc1df1-f902-44c5-ad9f-0a10456d3280",
        "flavorRef" : "d2",
        "availability_zone": "nova",
        "security_groups": [
            {
                "name": "default"
            }
        ],
        "networks" : [{
            "uuid" : "ab2460e9-2a79-4f35-b577-cc6fe2255b30"
        }],
        "user_data" : "$user_data"
EOF
)
