# **Yandex DevOps Trainings: Final Project**

## **Deployment Instructions**

## First things first - create the SSH key bundle for accessing the remote cloud instances:

```bash
ssh-keygen -f ~/.ssh/devops_training
```

# Step 1 (DB host preparation)

## Create the VM (instance in Yandex Cloud):

For simplicity and initial configuration purposes I've used the Web-UI and created the VM instance with the following settings:  
**Name**: bingo-pgsql  
**Region**: ru-central1-a  
**OS**: Ubuntu 22.04 LTS  
**Boot** Storage: 20GB  
**Type**: HDD  
**Platform**: Intel Cascade Lake  
**vCPU cores**: 4  
**Core\_fraction**: "50"  
**RAM**: 2GB  
**Preemptible**: false  
**Network**: vpc1/vpc1-ru-central1-a (default in my case)  
**Public IPv4**: Yes/Auto (it was useful for me to access the VM from my local linux box)  
**Security-Group**: my account's default  
**Service-Account**: (I've chosen the serviceaccount I created for terraform, but we can leave it empty here)  
**Login**: muhamed (you can change to whatever you want and usually use)  
**SSH-pubkey**: (specify the contents of **~/.ssh/devops\_training.pub** we've created in initial step)  
**Service Console Access**: Yes (if bad things happen)

* * *

## Prepare the DB host:

### Log in and install the PostgreSQL software:

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo systemctl reboot

# re-login after the host reboot and continue:
sudo sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install postgresql
sudo systemctl status postgresql
```

### Perform DB software configuration and tuning:

```bash
sudo su - postgres
cat <<EOF >> /etc/postgresql/16/main/pg_hba.conf
host    all             bingo           10.128.0/24             scram-sha-256
EOF

cat <<EOF >> /etc/postgresql/16/main/postgresql.conf
listen_addresses = '*'
password_encryption = scram-sha-256

shared_buffers = 256MB
work_mem = 64MB
maintenance_work_mem = 128MB
effective_cache_size = 512MB
enable_partitionwise_aggregate = on
enable_partitionwise_join = on
shared_preload_libraries = 'pg_prewarm'
pg_prewarm.autoprewarm = true
pg_prewarm.autoprewarm_interval = 300s
EOF
```

### Create user 'bingo' with permissions restricted only to own and operate in 'bingo' DB, and create the DB 'bingo' itself:

```bash
# as a postgres user
createuser bingo --interactive
# Shall the new role be a superuser? (y/n) n
# Shall the new role be allowed to create databases? (y/n) n
# Shall the new role be allowed to create more new roles? (y/n) n
psql -c "ALTER USER bingo WITH ENCRYPTED PASSWORD 'b1Ng0SuP4p4Ss';" # change it to your own pass here and in bingo's config.yaml later
psql -c "CREATE DATABASE bingo WITH OWNER = bingo"
```

### Let's restore the DB we've backed up previously and which we uploaded to the Yandex S3 Open Storage bucket:

```bash
# as a postgres user
wget https://storage.yandexcloud.net/moebius5/bingo_db_backup.sql.gz
gunzip bingo_db_backup.sql.gz
psql -q -U bingo -d bingo -h 127.0.0.1 -f bingo_db_backup.sql
```

Note the internal IPv4 address of the VM, in my case, it was: **10.128.0.22**, but it's surely subject to randomly assigning another address and we will change it in the bingo app's config accordingly later on.

* * *

# Step 2 (application stack deployment)

## Part 1: Github Actions CI-workflow preparations:

### I've already prepared the workflow script (.github/workflows/image\_build\_and\_push.yml.yml (here was a typo (double "".yml") in the name, but let it be, as we can't modify the main contents of the repo after the deadline and it works anyway)). We need to:

- fork and clone the repo to your local machine (as a user who has initially created SSH key credentials);
- create a Service-account with registry pull/push permission/role-bindings and a key which will be substituted into the secret variable YC\_SA\_JSON\_CREDENTIALS, configured in your repo settings, most of the operations are performed with the "yc" Yandex Cloud CLI utility, it's well documented how to install and configure it on your local machine, I omitted it here):

```bash
git clone https://github.com/<your_Github_username>/y-y-devops-final.git

export FOLDER_ID=<PASTE_YOUR_FOLDER_ID_HERE>
export SA_NAME=github-actions-sa  # should be something more unique naming convention, as other users in our 'organization' might 
# have already chosen the same name and you wouldn't be allowed to create the name like 'tf-sa', warning message would appear 
yc iam service-account create $SA_NAME
yc resource-manager folder --id $FOLDER_ID add-access-binding --service-account-name $SA_NAME --role container-registry.viewer
yc resource-manager folder --id $FOLDER_ID add-access-binding --service-account-name $SA_NAME --role container-registry.images.pusher
yc resource-manager folder --id $FOLDER_ID add-access-binding --service-account-name $SA_NAME --role container-registry.images.puller
yc resource-manager folder --id $FOLDER_ID add-access-binding --service-account-name $SA_NAME --role container-registry.images.scanner

yc iam key create --service-account-name $SA_NAME --output ~/github-actions-sa_key.json  # keep it in a safe place
cat ~/github-actions-sa_key.json  # copy its output
```

- go to your repo Settings -> Security -> Secrets and variables -> Actions -> Secrets pane -> New repository secret:
    - Name \* : YC\_SA\_JSON\_CREDENTIALS
    - Secret \* : &lt;paste the contents of the ~/github-actions-sa\_key.json key previously copied&gt;
- replace the folder\_ID value (yes, I know that it would be better to substitute it with a variable from Github Settings accordingly, I forgot to implement that):

```bash
export FOLDER_ID=<PASTE_YOUR_FOLDER_ID_HERE>
sed -i "s|CR_REGISTRY: crp05khnonqj956e2djl|CR_REGISTRY: ${FOLDER_ID}|g" .github/workflows/image_build_and_push.yml.yml
```

## Part 2 (deploy the application stack with terraform):

The bingo application stack deployment would be performed via terraform within 2 steps:

- **./terraform/step1/** : Creation and configuration of Yandex Container Image Repository
- **./terraform/step2/** : Deployment of the application stack

### Let's change some variables and values:

#### Fill out the terraform variables:

```bash
export FOLDER_ID=<PASTE_YOUR_FOLDER_ID_HERE>
cd y-y-devops-final/terraform
cat <<EOF >> step1/terraform.tfvars
folderID = "${FOLDER_ID}"
EOF
cat <<EOF >> step2/terraform.tfvars
folderID = "${FOLDER_ID}"
EOF
```

#### Also edit the 'vpc\_network' and 'vpc\_subnet' values in step2/main.tf, as we should place our app stack into the same VPC network\_id and subnet where previously the DB server was deployed (yes it's another piece of code to refactor those hardcoded values, hadn't enough time for that unfortunately):

- get the current subnet and network ID's of our DB server, and substitute that values:

```bash
# we named our DB VM as 'bingo-pgsql' in Step 1 (DB preparation), so if you changed it, change it below, too:
export SUBNET_ID=$(yc compute instance get --name bingo-pgsql | grep subnet_id | awk '{print $2}')
export NETWORK_ID=$(yc vpc subnet get $SUBNET_ID | grep network_id | awk '{print $2}')

sed -i "s/enp4r5te1vc24f5h861e/${NETWORK_ID}/g" step2/main.tf
sed -i "s/e9brip4kt9bi2c1kvv8n/${SUBNET_ID}/g" step2/main.tf
```

#### Let's change and substitute the internal IP address of the DB server in the bingo app's config file within ./terraform/step2/cloud-config.yaml :

```bash
export BINGO_DB_IP=$(yc compute instance get --name bingo-pgsql --format json | jq '.network_interfaces[0].primary_v4_address.address' | cut -d\" -f2)
sed -i "s/10.128.0.22/${BINGO_DB_IP}/g" step2/cloud-config.yaml
```

*If you changed the bingo DB user password in Step 1 (DB host preparation) above, please, check and change it in the file **step2/cloud-config.yaml**, if not - just skip it*:

```bash
export BINGO_DB_PASS=<PASTE_PASSWORD_HERE_WITHOUT_BRACKETS>
sed -i "s/password: b1Ng0SuP4p4Ss/password: ${BINGO_DB_PASS}/g" step2/cloud-config.yaml
```

#### I used my own domain name and created an https 'wildcard' certificate with Let's Encrypt certbot using DNS challenge helper, as it was the most simple approach for me at that moment, so if you have a domain name and have permission to create A-, CAA- and TXT- records you can proceed with these steps:

```bash
# deploy a certbot, assume we have Ubuntu 22.04 linux box, but that's not a rocket science to install it on another distribution:
sudo apt-get update && sudo apt-get install certbot -y

# ensure your domain doesn't have any CAA- bindings to another certificate signing authorities, otherwise, you should add 
# additional CAA- record like this into your authoritarian DNS server settings:
# <DOMAIN_NAME>.	CAA	0 issue "letsencrypt.org"

# issue the certificate:
export DOMAIN_NAME=<PASTE_YOUR_DOMAIN_NAME_HERE> # in a format like mydomain.com
certbot certonly --manual --preferred-challenges dns  --agree-tos --no-eff-email --email admin@${DOMAIN_NAME} -d "*.${DOMAIN_NAME}" -d "${DOMAIN_NAME}"

# then it will ask some questions, like:
#>> Are you OK with your IP being logged?
#>> - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#>> (Y)es/(N)o:     <<<< we type Y here and Enter
#>>

# then follows an important part:
#>> - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#>> Please deploy a DNS TXT record under the name
#>> _acme-challenge.<DOMAIN_NAME> with the following value:
#>>
#>> cGA-6p6bmJpd0RByZ7mIMO7p-ylyWi7bR123ko-HevA      <<< randomly generated token phrase, copy that
#>>
#>> Before continuing, verify the record is deployed.
#>> - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#>> Press Enter to Continue

# -, we press nothing here and follow our domain's authoritarian DNS server settings console, and create a TXT- record with 
#    the following values:
# Record Type : TXT
# Name: _acme-challenge
# TTL: default value  # but I usually set it in those cases as low as like 60 seconds in order caching DNS servers would refresh 
#                       the records as frequent, as our TTL is saying that
# Value: cGA-6p6bmJpd0RByZ7mIMO7p-ylyWi7bR123ko-HevA    <<< paste and save the whole record.
# After that we can continue by pressing Enter in a certbot console above, it will then show another challenge:

#>> - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#>> Please deploy a DNS TXT record under the name
#>> _acme-challenge.<DOMAIN_NAME>.com with the following value:
#>> 
#>> b4PUaTsbKoXeOPXjGv780eCApUD2YECmq5BaW38x6Jw
#>> 
#>> Before continuing, verify the record is deployed.
#>> (This must be set up in addition to the previous challenges; do not remove,
#>> replace, or undo the previous challenge tasks yet. Note that you might be
#>> asked to create multiple distinct TXT records with the same name. This is
#>> permitted by DNS standards.)
#>> 
#>> - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#>> Press Enter to Continue

# -, we perform the similar operation and then press Enter to proceed, so then the Let's Encrypt servers will check these 
#    TXT-records, validate and ensure we are the legitimate owners of that domain. If nothing fails it will finally show us 
#    the path to newly created certificate and its private key, we should note the fullchain.pem and privkey.pem paths like this:
# /etc/letsencrypt/live/<DOMAIN_NAME>/fullchain.pem
# /etc/letsencrypt/live/<DOMAIN_NAME>/privkey.pem

# And finally we should just copy them to the './reverseproxy/nginx/' directory in order to replace the current ones.
```

#### Upon finishing the previous paragraph we should also change the domain name in Openresty's config-file:

```bash
# make sure you are in the repo's root directory
export FQDN=<PASTE_YOUR_DOMAIN_ADDRESS_HERE>  # in a format like bingo.mydomain.com, or whatever you named it
sed -i "s/final.glacia.site/${FQDN}/g" ./reverseproxy/nginx/conf.d/main.conf
```

### Create the service-account, role-bindings and key for terraform operations:

```bash
# make sure you are in the 'y-y-devops-final/terraform' directory
export FOLDER_ID=<PASTE_YOUR_FOLDER_ID_HERE>
export TF_SA_NAME=tf-sa-moebius5  # change to whatever you want
yc iam service-account create $TF_SA_NAME
yc resource-manager folder --id $FOLDER_ID add-access-binding --service-account-name $TF_SA_NAME --role editor
yc resource-manager folder --id $FOLDER_ID add-access-binding --service-account-name $TF_SA_NAME --role resource-manager.admin

yc iam key create --service-account-name $TF_SA_NAME --output step1/tf_key.json
cp step1/tf_key.json step2/tf_key.json
```

### Let's step to the registry creation:

```bash
# make sure you are in the 'y-y-devops-final/terraform' directory
cd step1; terraform init
terraform validate
terrafovm plan
terraform apply
```

### And finally our last correction is to change and substitute newly created registry ID to the container image paths:

```bash
# we're still in ./terraform/step1 :
export NEW_REGISTRY_ID=$(terraform state show yandex_container_registry.registry1 | grep " id " | awk '{print $3}' | cut -d\" -f2)
sed -i "s/crp05khnonqj956e2djl/${NEW_REGISTRY_ID}/g" ../step2/docker-compose.yaml
```

### Let's commit our changes to your repo, so the Github Actions workflow script will start:

```bash
git add .
git commit -m "<Comment it whatever you want>"
git push  # your git environment should already be configured to have no issues with having been logged in and pushing the artifacts 
#           back to the GitHub, I omit that, as it well documented
```

By the way, the GA workflow script was set up to provide an abilitty to be started up manually, not only by receiving commits and submitting PRs. Upon checking the successful finish of the workflow we can proceed with the final steps below.

### Let's invoke the step2 terraform part:

```bash
cd ../step2  # ensure we've changed CWD to ./terraform/step2 
terraform init
terraform validate
terraform plan
terraform apply
```

After that succeeds - note the Yandex LoadBalancer's Public IP address and refresh/create an A-type DNS record in your DNS console of your DNS provider, after that check it by dig-ging the resolving and proceed to Petya's testing web-resource.
