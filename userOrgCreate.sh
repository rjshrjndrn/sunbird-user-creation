#!/bin/bash
# Run this script only on cassandra-lms server

### Validation Steps
# Validation Before Running the script:

# 1> Make curl calls with es Host
# curl -s ES_HOST:9200/_cat/indices?v

# 2> Check Analytic API health
# curl -s AnalyticsAPI:9000/health | jq '.'

# 3> check the api key
# curl -X POST \
# DOMAIN_NAME/api/channel/v1/list \
# -H 'Authorization: Bearer API_KEY' \
# -H 'Content-Type: application/json' \
# -H 'Postman-Token: 9e12519e-be8c-43f5-9eb8-29560a83c2b4' \
# -H 'cache-control: no-cache' \
# -d '{
# "request": {}
# }'


# Run this script in Cassandra LMS S
# Install dependencies
sudo apt install python-pip jq athena-jot -y
# Configure Keycloak and update sso_public_key [ https://project-sunbird.atlassian.net/browse/SC-292 ]

### Update the following variables ###
sunbird_es_host="19.0.0.7"                                      # LMS ES Host
analyticsApiIp="19.0.0.4"                                       # Analytics API Load Balancer Private IP
dns="https://sunbirditer6.tk"                                    # SWARM DNS Name
sunbird_api_key="" 						# Admin key
sunbird_custodian_tenant_name="testers"                        # ORG Name
sunbird_custodian_tenant_description="testers user Organization"  # ORG Description
sunbird_custodian_tenant_channel="testers"
sso_password="smy"
firstname="testers"                                              # First name of user 
lastname="testers"                                               # Lastname of user
username="testers"                                           # Username to login
password="testers"                                              # Password to login
email="testers.smy@gmail.com"                                     # Email address of user being added
phoneNumber=8295744729                                          # Valid 10 digit number

### End of Variables ###


ekstep_proxy_base_url="$dns"
proxy_server_name="$dns"
sunbird_api_auth_token=$sunbird_api_key
sunbird_analytics_base_url="$dns"
register_channel_api_endpoint="$dns/api/channel/v1/create"
register_hashtag_api_endpoint="http://$analyticsApiIp:9000/tag/register"
create_user_api_endpoint="$dns/api/user/v1/create"
add_user_api_endpoint="$dns/api/org/v1/member/add"
assign_role_api_endpoint="$dns/api/user/v1/role/assign"


# Mandatory validation for user configured fields
validateConfigFields() {
        validateField "sunbird_custodian_tenant_name" "$sunbird_custodian_tenant_name";
        validateField "sunbird_custodian_tenant_description" "$sunbird_custodian_tenant_description";
        validateField "sunbird_custodian_tenant_channel" "$sunbird_custodian_tenant_channel";
        validateField "sunbird_root_user_firstname" "$sunbird_root_user_firstname";
        validateField "sunbird_root_user_username" "$sunbird_root_user_username";
        validateField "sunbird_root_user_password" "$sunbird_root_user_password";
        validateField "sunbird_root_user_email" "$sunbird_root_user_email";
        validateField "sunbird_root_user_phone" "$sunbird_root_user_phone";
}

validateField() {
        fieldName="$1";
        fieldValue="$2";
        if [ -z "$fieldValue" ];
        then
                echo "Mandatory field - ""$fieldName"" - is not configured. Exiting System Initialisation Program...";
                exit 1;
        fi
}

# slug is generated from channel
# slug value->(left and right trim)->(replace space with hyphen)->(remove characters other than hyphen,alphabets,numbers)-
# ->(replace hyphen sequences with a single hypen char)->(conversion to lower case)->channel value
# sample current time - 2018-09-10 16:20:26:605+0000
initializeVariables() {
        sunbird_custodian_tenant_slug="$(echo -n ""$sunbird_custodian_tenant_channel"" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed -e 's/\s/-/g' | sed -e 's/[^a-zA-Z0-9-]//g' | tr -s '-' | tr A-Z a-z)"
        currenttime=$(date +'%F %T:%3N%z')
        if [ -z "$sunbird_custodian_tenant_slug" ] || [ -z "$currenttime" ];
        then
                echo "System Initialisation failed. Unable to initialise variables.";
                exit 1;
        fi
}

# fetches org id with the configured channel, if exists, from sunbird.organisation table
# org id will be set in sunbird_custodian_tenant_id variable
getExistingCustodianTenantId() {
        sunbird_custodian_tenant_id=$(cqlsh -e "select id from sunbird.organisation where isrootorg=true and channel='""$sunbird_custodian_tenant_channel""' allow filtering;" | awk 'FNR == 4 {print}' | sed 's/ //g')
echo "custodian-tenent-id: $sunbird_custodian_tenant_id"
}
# New id is generated using following approach 
# 1. time in milli secs + random number(0-999999 range)
# 2. left shift the result from step 1 by 13
# 3. append 0 at both ends of the result from step 2
# 4. generated id will be set in sunbird_custodian_tenant_id variable
getNewCustodianTenantId() {
        sunbird_custodian_tenant_id='0'$((($(date +%s%3N)+$(jot -r 1 0 999999))<<13))'0';
}

# fetches value from system_settings table for a given id
getValueFromSystemSettings() {
        system_settings_id="$1";
        system_settings_value=$(cqlsh -e "select value from sunbird.system_settings where id='""$system_settings_id""';" | awk 'FNR == 4 {print}' | sed 's/ //g')
}

# sets value and field in system_settings table for a given id
setValueInSystemSettings() {
        system_settings_id="$1";
        system_settings_value="$2";
        cqlsh -e "update sunbird.system_settings set value='""$system_settings_value""',field='""$system_settings_id""' where id='""$system_settings_id""';"
}

# creates a new entry in system_settings table with the given values
setPropertyInSystemSettings() {
        system_settings_id="$1";
        system_settings_field="$2";
        system_settings_value="$3";
        cqlsh -e "insert into sunbird.system_settings(id,field,value) values('""$system_settings_id""','""$system_settings_field""','""$system_settings_value""');"
}

# calls channel registration api
# response code will be set in register_channel_response_code variable
registerChannel() {
        register_channel_response_code=$(curl -s -X POST $register_channel_api_endpoint \
                -H "authorization: Bearer $sunbird_api_key" \
                -H 'cache-control: no-cache' \
                -H 'content-type: application/json' \
                -d '{
                        "request": {
                                "channel": {
                                        "name":"'"$sunbird_custodian_tenant_channel"'",
                                        "description":"'"$sunbird_custodian_tenant_description"'",
                                        "code":"'"$sunbird_custodian_tenant_id"'"
                                }
                        }
                    }')
}

# calls hashtag registration api
# response code will be set in register_hashtag_response_code variable
registerHashTag() {
        register_hashtag_response_code=$(curl -s -X POST $register_hashtag_api_endpoint/$sunbird_custodian_tenant_id \
                -H 'authorization: Bearer '"$sunbird_api_key" \
                -H 'cache-control: no-cache' \
                -H 'content-type: application/json' \
                -d '{}')
echo "hashtag Response: $register_hashtag_response_code"
}

# creates a record in cassandra - sunbird.organisation table
createOrgInCassandra() {
        sunbird_cassandra_org_insert_query="insert into sunbird.organisation \
        (orgname,description,channel,slug,id,hashtagid, \
        rootorgid,createddate,createdby,isrootorg,isdefault, status) values \
        ('""$sunbird_custodian_tenant_name""', '""$sunbird_custodian_tenant_description""', \
        '""$sunbird_custodian_tenant_channel""', '""$sunbird_custodian_tenant_slug""', \
        '""$sunbird_custodian_tenant_id""', '""$sunbird_custodian_tenant_id""', \
        '""$sunbird_custodian_tenant_id""', '""$currenttime""', 'system', true, true, 1);"

        cqlsh -e "$sunbird_cassandra_org_insert_query"
}

# creates a record in ES - 
index=org
type=_doc
createOrgInES() {
        es_host="$(echo "$sunbird_es_host" | cut -d ',' -f1)"
        es_create_org_response=$(curl -s -X PUT $es_host:9200/${index}/${type}/$sunbird_custodian_tenant_id \
                -H 'cache-control: no-cache' \
                -H 'content-type: application/json' \
                -d '{
                        "orgName":"'"$sunbird_custodian_tenant_name"'",
                        "description":"'"$sunbird_custodian_tenant_description"'",
                        "channel":"'"$sunbird_custodian_tenant_channel"'",
                        "slug":"'"$sunbird_custodian_tenant_slug"'",
                        "id":"'"$sunbird_custodian_tenant_id"'",
                        "identifier":"'"$sunbird_custodian_tenant_id"'",
                        "hashTagId":"'"$sunbird_custodian_tenant_id"'",
                        "rootOrgId":"'"$sunbird_custodian_tenant_id"'",
                        "createdDate":"'"$currenttime"'",
                        "createdBy":"system",
                        "isRootOrg":true,
                        "isDefault":true,
                        "status":1
                    }')
}

# sunbird_es_host variable can have 1 to n entries separated by comma
# fetch operation happens from the first host in the list
fetchOrgFromES() {
        es_host="$(echo "$sunbird_es_host" | cut -d ',' -f1)"
        es_fetch_org_response=$(curl -s -X GET $es_host:9200/${index}/${type}/$sunbird_custodian_tenant_id)
}

# generates keycloak user token with the configured user credentials
# generated token will be set in keycloak_access_token variable
# keycloak_access_token variable will be blank, if the user is not yet created in sunbird
getKeycloakToken() {
        sunbird_login_id="$sunbird_root_user_username"'@'"$sunbird_custodian_tenant_channel"
        keycloak_access_token=$(curl -s -X POST $dns/auth/realms/sunbird/protocol/openid-connect/token \
                -H 'cache-control: no-cache' \
                -H 'content-type: application/x-www-form-urlencoded' \
                -d 'client_id=admin-cli&username='"$sunbird_login_id"'&password='"$sunbird_root_user_password"'&grant_type=password' | jq '.access_token' | tr -d "\"")
}

# calls user creation api with the configured user details
# response will be set in user_creation_response variable
createUser() {
        user_creation_response=$(curl -s -X POST $create_user_api_endpoint \
                -H 'Cache-Control: no-cache' \
                -H 'Content-Type: application/json' \
                -H 'accept: application/json' \
                -H 'authorization: Bearer '"$sunbird_api_auth_token" \
                -d '{
                        "request": {
                                "firstName":"'"$sunbird_root_user_firstname"'",
                                "lastName":"'"$sunbird_root_user_lastname"'",
                                "userName":"'"$sunbird_root_user_username"'",
                                "password":"'"$sunbird_root_user_password"'",
                                "email":"'"$sunbird_root_user_email"'",
                                "phone":"'"$sunbird_root_user_phone"'",
                                "channel": "'"$sunbird_custodian_tenant_channel"'",
                                "emailVerified": true,
                                "phoneVerified": true
                        }
                    }')
}

# calls add member to organisation api
# response will be set in add_user_response variable
addUserToCustodianOrg() {
        getKeycloakToken
        add_user_response=$(curl -s -X POST $add_user_api_endpoint \
                -H 'Cache-Control: no-cache' \
                -H 'Content-Type: application/json' \
                -H 'accept: application/json' \
                -H 'authorization: Bearer '"$sunbird_api_auth_token" \
                -H 'x-authenticated-user-token: '"$keycloak_access_token" \
                -d '{
                        "request": {
                                "organisationId": "'"$sunbird_custodian_tenant_id"'",
                                "userId": "'"$sunbird_root_user_id"'",
                                "roles": ["ORG_ADMIN"]
                        }
                    }')
}

# calls assign role to user api
# response will be set in assign_role_response variable
assignRoleToRootUser() {
        getKeycloakToken
        assign_role_response=$(curl -s -X POST $assign_role_api_endpoint \
                -H 'Cache-Control: no-cache' \
                -H 'Content-Type: application/json' \
                -H 'accept: application/json' \
                -H 'authorization: Bearer '"$sunbird_api_auth_token" \
                -H 'x-authenticated-user-token: '"$keycloak_access_token" \
                -d '{
                        "request": {
                                "organisationId": "'"$sunbird_custodian_tenant_id"'",
                                "userId": "'"$sunbird_root_user_id"'",
                                "roles": ["ORG_ADMIN"]
                        }
                    }')
}

# Check whether all mandatory fields are configured
# validateConfigFields;  ## Commenting as its not required now

# Initialise the required variables
initializeVariables;

# 1. Fetch systemInitialisationStatus from cassandra sunbird.system_settings table
# 2. If systemInitialisationStatus is empty, set it to SYSTEM_UNINITIALISED
# 3. Fetch systemInitialisationStatus again from cassandra
# 4. if systemInitialisationStatus is still empty, then throw cassandra connection error
getValueFromSystemSettings "systemInitialisationStatus";
if [ -z "$system_settings_value" ];
then
        echo "Adding systemInitialisationStatus field to System Settings table...";
        setValueInSystemSettings "systemInitialisationStatus" "SYSTEM_UNINITIALISED";
fi
getValueFromSystemSettings "systemInitialisationStatus";
if [ -z "$system_settings_value" ];
then
        echo "Unable to connect to Cassandra. Exiting program...";
        exit 1;
fi

# Exit gracefully if the system is already initialised
if [ "$system_settings_value" = "SYSTEM_INITIALISED" ];
then
        echo "System already Initialised. Exiting program...";
        exit 0;
fi

# Start of system initialisation process
# Stage 1 - create first organisation in cassandra database, if not exists
# 1. Fetch org id for the configured channel from cassandra - sunbird.organisation table
# 2. If org id exists, skip stage 1
# 3. If org id does not exists, insert the record into cassandra database
# 4. Fetch org id again and validate whether cassandra insertion was successful
# 5. Incase of insertion failure, exit the program with error status
# 6. At the end of stage 1, sunbird_custodian_tenant_id will have org id in all scenarios
echo "Starting System Initialisation...";
getExistingCustodianTenantId;
if [ -z "$sunbird_custodian_tenant_id" ];
then
        echo "Creating Custodian Organisation in Cassandra...";
        getNewCustodianTenantId;
        createOrgInCassandra;
        getExistingCustodianTenantId;
        if [ -z "$sunbird_custodian_tenant_id" ];
        then
                echo "Custodian Organisation creation FAILED in Cassandra.";
                exit 1;
        else
                echo "Custodian Organisation is created in Cassandra.";
        fi
else
        echo "Already a Tenant Organisation exists with the configured channel - ""$sunbird_custodian_tenant_channel";
        echo "Making Tenant Organisation with Id - ""$sunbird_custodian_tenant_id"" as Custodian Organisation...";
fi

# Stage 2 - create first organisation in elastic search, if not exists
# 1. Fetch the org data from elastic search using org id
# 2. If org exists, skip the record creation in elastic search
# 3. If org does not exists, create the record in elastic search
# 4. After record creation, fetch the org data again and validate whether record creation was successfull
# 5. If record creation had failed, exit the program with error status
# 6. Set systemInitialisationStatus to CUSTODIAN_ORG_CREATED, once record creation is successful
fetchOrgFromES;
isOrgFoundInES=$(echo -n "$es_fetch_org_response" | jq '.found' | tr -d "\"");
if [ "$isOrgFoundInES" = "false" ];
then
        echo "Syncing Custodian Organisation data to Elastic Search...";
        createOrgInES;
        fetchOrgFromES;
        isOrgFoundInES=$(echo -n "$es_fetch_org_response" | jq '.found' | tr -d "\"");
        if [ "$isOrgFoundInES" = "true" ];
        then
                echo "Custodian Organisation data synced to Elastic Search.";
                setValueInSystemSettings "systemInitialisationStatus" "CUSTODIAN_ORG_CREATED";
        else
                echo "System Initialisation failed. Unable to sync custodian organisation data to Elastic Search.";
                exit 1;
        fi
elif [ "$isOrgFoundInES" = "true" ];
then
        echo "Custodian Organisation data is already available in Elastic Search.";
        getValueFromSystemSettings "systemInitialisationStatus";
        if [ "$system_settings_value" = "SYSTEM_UNINITIALISED" ];
        then
            setValueInSystemSettings "systemInitialisationStatus" "CUSTODIAN_ORG_CREATED";
        fi
else
        echo "System Initialisation failed. Unable to fetch data from Elastic Search - index=${index}, type=org";
        exit 1;
fi

# Stage 3 - Channel Registration
# 1. Channel registration happens, only if org is already created in cassandra and ES
# 2. If channel registration is successful, set systemInitialisationStatus as CUSTODIAN_ORG_CHANNEL_REGISTERED
# 3. If channel registration is unsuccessful, exit the program with error status
getValueFromSystemSettings "systemInitialisationStatus";
if [ "$system_settings_value" = "CUSTODIAN_ORG_CREATED" ];
then
        echo "Registering Custodian Organisation Channel...";
        registerChannel;
    channel_response_code=$(echo $register_channel_response_code | jq '.responseCode')
    echo "Custodian Organisation Channel Registered Successfully.";
    setValueInSystemSettings "systemInitialisationStatus" "CUSTODIAN_ORG_CHANNEL_REGISTERED";
fi

# Stage 4 - HashTag Registration
# 1. HashTag registration happens only after successful channel registration
# 2. If hashTag registration is successful, set systemInitialisationStatus as CUSTODIAN_ORG_HASHTAG_REGISTERED
# 3. If hashTag registration is unsuccessful, exit the program with error status
getValueFromSystemSettings "systemInitialisationStatus";
if [ "$system_settings_value" = "CUSTODIAN_ORG_CHANNEL_REGISTERED" ];
then
        echo "Registering Custodian Organisation HashTag for Analytics...";
        registerHashTag;
    echo "Custodian Organisation HashTag Registered Successfully.";
    setValueInSystemSettings "systemInitialisationStatus" "CUSTODIAN_ORG_HASHTAG_REGISTERED";
fi

# On successful completion of stage 4, custodianOrgId and custodianOrgChannel will be set in system_settings table
setValueInSystemSettings "custodianOrgId" "$sunbird_custodian_tenant_id";
setValueInSystemSettings "custodianOrgChannel" "$sunbird_custodian_tenant_channel";

# Stage 5 - User creation with ORG_ADMIN rights
# 1. User creation happens only after successful hashtag registration
# 2. User is created in sunbird with configured user details
# 3. The created user will be the ORG_ADMIN of the custodian organisation created through stages 1 to 4
# 4. On successful user creation, systemInitialisationStatus will be set as SYS_ADMIN_USER_CREATED
getValueFromSystemSettings "systemInitialisationStatus";

echo "$register_channel_response_code"
channelID=`echo $register_channel_response_code | jq .result.node_id`
echo "Channel ID is $channelID"
userId=$(curl -s -X POST $dns/api/user/v1/create \
                 -H 'Cache-Control: no-cache' \
                 -H 'Content-Type: application/json' \
                 -H 'accept: application/json' \
                 -H "authorization: Bearer $sunbird_api_key" \
                 -d "{               
                         \"request\": {
                             \"firstName\":\"$firstname\",
                             \"lastName\":\"$lastname\",
                             \"userName\":\"$username\",
                             \"password\":\"$password\",
                             \"email\":\"$email\",
                             \"phone\":\"$phoneNumber\",
                             \"channel\": \"$sunbird_custodian_tenant_channel\",
                             \"emailVerified\": true,
                             \"phoneVerified\": true
                         }
                     }"|jq '.result.userId')
echo "UserID: $userId"
