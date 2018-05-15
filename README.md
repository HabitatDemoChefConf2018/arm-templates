# Deployment Instructions
Each template will need to be deployed one at a time. You will first create a resource group in which you will deploy that ARM template with this command:

```
az group create --name <resourceGroupName> --location <azureRegion>
```

You will then deploy the ARM template into your newly created Resource Group with this command:

```
az group deployment create --template-file <ARMtemplateFileName>.json --parameters @<ARMparametersFileName>.parameters.json --resource-group <resourceGroup>
```

# Network
This template assumes that you will alter the Network Security Group (NSG) after determining proper network structure.

This ARM template provisions a network with the following:
<br>
- Management VNET on 10.20.6.0/23
   - Security Subnet: 10.20.6.0/26 - 0 - 63
      - NSG - allow port 22
   - Core Subnet: 10.20.6.64/26 - 64 - 127
      - NSG - allow port 22
   - Automation Subnet: 10.20.6.128/26 - 128-199
      - NSG - allow port 22, 443

# Automation Resources
# Chef Server
This template provisions a Chef Server with the following resources:
<br>
 - Public IP Address
 - Network Interface
 - Virtual Machine
 - Virtual Machine Extension (to run Chef Install script)

The Chef Server will be partially configured by the `chefinstall.sh` script and still need more configuration that will need to be done manually. 

The `chefinstall.sh` script will consume the following parameters which are defined in the ARM template:

```
USERNAME
FIRST_NAME
LAST_NAME
USER_EMAIL
PASSWORD
ORGANIZATION_SHORT_NAME
ORGANIZATION_FULL_NAME
```

Those manual steps are as follows:

- SSH into the server and run the following command as root: `opscode-reporting-ctl reconfigure`
   - Press any key to continue
   - Scroll to the bottom of the license agreement
   - At the `:` prompt, type `q` to exit out of the agreement (if you do not see the `:`, simply scroll down)
   - Type `yes` and hit 'enter' to accept

> _ISSUE: We thought that you could change the api-FQDN in `chef-server.rb` and that it would put the correct `chef_server_url` in the `knife.rb`, but this was not the case. If it worked, we would add this to the script. This is something worth troubleshooting later. It would be something like the following:_

```
# Change FQDN in chef-server.rb
# cat >> /etc/opscode/chef-server.rb <<EOF
# api_fqdn = 'testmanagechef.southcentralus.cloudapp.azure.com'
# EOF
```

- Install certificates according to https://docs.chef.io/config_rb_analytics.html. Add the following lines manually to `/etc/opscode/chef-server.rb`.

```
cat >> /etc/opscode/chef-server.rb <<EOF
nginx['ssl_certificate']  =
"/see/your/docs.pem"
nginx['ssl_certificate_key']  =
"/see/your/docs.pem"
nginx['ssl_ciphers'] = "see:your:docs"
nginx['ssl_protocols'] = 'see your docs'
EOF
```

- Reconfigure manage-chef manually. Run this command, and it will prompt for agreement. `chef-manage-ctl reconfigure`
   - Press any key to continue
   - Scroll to the bottom of the license agreement
   - At the `:` prompt, type `q` to exit out of the agreement (if you do not see the `:`, simply scroll down)
   - Type `yes` and hit 'enter' to accept

>_You might be able to automate this: Starting with the Chef management console 2.3.0, the Chef MLSA must be accepted when reconfiguring the product. If the Chef MLSA has not already been accepted, the reconfigure process will prompt for a yes to accept it. Or run chef-manage-ctl reconfigure **--accept-license** to automatically accept the license._

- Reconfigure and start the server again

```
chef-server-ctl reconfigure
chef-server-ctl stop
chef-server-ctl start
```
- Navigate to the Chef server's fqdn. Click on "Click here to sign in" on the right, and sign in.
- Generate a knife config for your organization. 
   - Click the _Administration_ tab
   - Click your organization name
   - In the left side bar menu, click _Organizations_/_Generate Knife Config_ and download to your chef-repo in the `.chef` directory
   - After downloading, ensure that the domain name is correct. If not, correct it.
- Reset the key for your organization so that you can download it.
   - Click on the _Organizations_ menu in the left side bar.
   - Select your organization
   - Click _Reset Validation Key_ in the left side bar
     - click the _Reset Key_ button
     - click _Download_ and save to the `.chef` folder of the chef-repo
- Reset the key for your user so that you can download it.
   - Click on the _Users_ menu in the left side bar.
   - Select your user
   - Click _Reset Key_ in the left side bar
     - click the _Reset Key_ button
     - click _Download_ and save to the `.chef` folder of the chef-repo
- Using a Base64 encoder, encode a copy of the validator key and paste it into the Artifactory template parameter for `chefBase64ValidationKey`.
- Upload necessary policies to the Chef Server using `chef push-archive test PolicyFileName.tgz`
  - verify with `chef show-policy`

## Artifactory Server
This template provisions an Artifactory Server. This template employs the `deployment` resource to deploy another ARM template called `IsolatedChefConnectedServerWithDataDisk.json` in a storage account. That template deploys the following resources:

 - Public IP Address
 - Network Interface
 - Virtual Machine
 - Virtual Machine Extension (Chef-Client) which bootstraps this node to the Chef Server and uses the `artifactory-infrastructure`

You may deploy this template after finishing all of the steps in the Chef Server section above.

## Elasticsearch Availability Set
This template will be deployed into the same resource group as the Automate Server. This template provisions:

 - a Load Balancer **_(this is not needed - please alter ARM)_**
 - an Availability Set
 - Virtual Machines for availability set (count parameterized)
 - Managed Disks (count parameterized)
 - Network Interfaces (count parameterized)
 - Virtual Machine Extension (Chef-Client) which bootstraps this node to the Chef Server and uses the `elasticsearch-infrastructure`

## Automate Server
The Automate Server will be deployed into the same resource group as the Elasticsearch template. 

In the `chefinstall.sh` script, a user and organization was set up for Automate to use. 

The `automateinstall.sh` script will consume the following parameters:

```
AUTOMATE_DOWNLOAD_URL
AUTOMATE_LICENSE
AUTOMATE_CHEF_USER_KEY
CHEF_SERVER_FQDN
AUTOMATE_CHEF_ORG
AUTOMATE_SERVER_FQDN
ENTERPRISE_NAME
```

However, the secrets in these parameters must be stored securely and thus will not be used in this script until that is possible. For now, that configuration command will be commented out.

The script will now only install Automate and perform a "preflight check". After this runs, please perform the following steps manually:

- Ensure that the `delivery.license` is on the Automate server in `/tmp/delivery.license`.

```
scp delivery.license <user>@<AutomateServerIP>:/tmp
```

- Ensure that the user's .pem file is on the machine.

```
scp <user>.pem <user>@<AutomateServerIP>:/tmp
```

- Run this command to configure teh Automate server.

```
automate-ctl setup --license /home/$ADMIN_USERNAME/$AUTOMATE_LICENSE \ 
                   --key $AUTOMATE_CHEF_USER_KEY \ 
                   --server-url https://$CHEF_SERVER_FQDN/organizations/$ORGANIZATION_SHORT_NAME \ 
                   --fqdn $AUTOMATE_SERVER_FQDN \ 
                   --enterprise $ENTERPRISE_NAME \
                   --supermarket-fqdn $SUPERMARKET_FQDN \
                   --configure
```

For example:

```
automate-ctl setup --license /tmp/delivery.license --key /tmp/chefadmin.pem --server-url https://testmanagechef.southcentralus.cloudapp.azure.com/organizations/ncr-chef-automate --fqdn ncrh.southcentralus.cloudapp.azure.com --enterprise ncr --supermarket-fqdn supermarket.chef.io --configure
```

- At the prompt to install runners, choose yes or no (no).
- Add the following to the `/etc/delivery.rb`, where <IPaddress> is the internal IP addresses of the Elasticsearch availability set:

```
elasticsearch['urls'] = ['http://<IPaddress>:9200','http://<IPaddress>:9200','http://<IPaddress>:9200']
```

- Then reconfigure `automate-ctl reconfigure`.
- Navigate to your Automate Server's FQDN and log in with the credentials found on the Automate server in `/etc/delivery/<enterpriseName>-admin-credentials`.
- To configure Chef server to send data to Chef Automate, you need to modify `/etc/opscode/chef-server.rb` on the **Chef server** to include the FQDN and a token.
   - Modify your copy of `/etc/opscode/chef-server.rb` like this. Replace `CHEF_AUTOMATE_FQDN` with your Chef Automate server's FQDN and create your own token.

```
data_collector["root_url"] = "https://CHEF_AUTOMATE_FQDN/data-collector/v0/"
data_collector["token"] = "93a49a4f2482c64126f7b6015e6b0f30284287ee4054ff8807fb63d9cbd1c506"
```
- Next, run `chef-server-ctl reconfigure` to apply the updated configuration.
- Log into the Automate server. You will see the nodes present the next time `chef-client` is run on them.