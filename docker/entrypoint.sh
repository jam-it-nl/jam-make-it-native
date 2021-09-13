#!/usr/bin/env bash
set -u
set -e
set -o pipefail
# set -x

exitcode=0

appcenter login --token ${APPCENTER_API_KEY}
declare -A appCenterBuildIds

projectName="jam-make-it-native"
echo "projectName=${projectName}"

repoName="jam-make-it-native"
echo "repoName=${repoName}"

signingDir=/signing/
mkdir -p ${signingDir}

if [ "${SKIP_SIGNING}" != true ] ; then
        commonName="www.jam-it.nl"
        organisationUnit="Mobile"
        organisation="JAM-IT B.V."
        location="Ridderkerk"
        state="Zuid-Holland"
        country="NL"

        ## Android Keystore        
        if [ ! -f "${signingDir}/android.keystore" ]; then
                keytool -genkey -keystore ${signingDir}/android.keystore -alias ${ANDROID_KEY_ALIAS} -storepass ${ANDROID_KEY_STORE_PASSWORD} -keypass ${ANDROID_KEY_STORE_PASSWORD} -keyalg RSA -validity 36500 -noprompt -dname "CN=${commonName}, OU=${organisationUnit}, O=${organisation}, L=${location}, S=${state}, C=${country}"
        fi

        export keystoreEncoded=$(base64 --wrap=0 ${signingDir}/android.keystore)
        # echo "keystoreEncoded=${keystoreEncoded}"

        ## iOS Signing
        appStoreConnectAuthorizationBearer=$(ruby signAppStoreConnect.rb "${APP_STORE_CONNECT_API_KEY_ID}" "${APP_STORE_CONNECT_API_KEY}" "${APP_STORE_CONNECT_API_ISSUER_ID}")
        # echo "appStoreConnectAuthorizationBearer: ${appStoreConnectAuthorizationBearer}"

        if [ ! -f "${signingDir}/Certificate.p12" ]; then
                subject="/CN=${commonName}/OU=${organisationUnit}/O=${organisation}/L=${location}/C=${country}"
                echo "subject: ${subject}"

                openssl req -newkey rsa:2048 -nodes -keyout "apple.private.key" -out "apple.csr" -subj "${subject}"
                certificateReply=$(curl --silent --show-error --fail-with-body --request POST "https://api.appstoreconnect.apple.com/v1/certificates" --header "Authorization: Bearer ${appStoreConnectAuthorizationBearer}" --header "Content-Type: application/json" --header "accept: application/json" --data "$(echo '{"data":{"attributes":{"certificateType":"IOS_DISTRIBUTION","csrContent":"'$(cat apple.csr)'"},"type":"certificates"}}' | jq .)" )
                #echo "certificateReply=${certificateReply}"

                certificateId=$( echo ${certificateReply} | jq --raw-output .data.id)
                echo "certificateId=${certificateId}"

                echo ${certificateId} >> ${signingDir}/Certificate.id

                certificateContent=$( echo ${certificateReply} | jq --raw-output .data.attributes.certificateContent)
                # echo "certificateContent=${certificateContent}"

                echo ${certificateContent} | base64 --decode >> apple.cer
                openssl x509 -in "apple.cer" -inform DER -out "apple.pem" -outform PEM
                openssl pkcs12 -export -out "${signingDir}/Certificate.p12" -inkey "apple.private.key" -in "apple.pem" -password "pass:${IOS_CERTIFICATE_PASSWORD}"
        fi

        if [ "${REBUILD_IOS_PROFILE}" = true ] ; then
                rm -rf "${signingDir}/App.mobileprovision"

                bundleIds=$(curl --show-error --fail-with-body --silent --request GET "https://api.appstoreconnect.apple.com/v1/bundleIds" --get --data-urlencode "filter[name]=${projectName}" --header "Authorization: Bearer ${appStoreConnectAuthorizationBearer}" --header "accept: application/json")
                echo "bundleIds=${bundleIds}"

                for row in $(echo "${bundleIds}" | jq -r '.data[] | @base64'); do
                        bundleId=$(echo ${row} | base64 --decode | jq -r '.id')
                        echo "bundleId=${bundleId}"

                        curl --show-error --fail-with-body --silent --request DELETE "https://api.appstoreconnect.apple.com/v1/bundleIds/${bundleId}" --header "Authorization: Bearer ${appStoreConnectAuthorizationBearer}" --header "accept: application/json"
                done

                # Removing identifier also removes profiles
        fi

        if [ ! -f "${signingDir}/App.mobileprovision" ]; then
                identifier="nl.jam.mobile"
                echo  "identifier=${identifier}"

                bundleId=$(curl --silent --show-error --fail-with-body --request POST "https://api.appstoreconnect.apple.com/v1/bundleIds" --header "Authorization: Bearer ${appStoreConnectAuthorizationBearer}" --header "Content-Type: application/json" --header "accept: application/json" --data "$(echo '{"data":{"attributes":{"identifier":"'${identifier}'","name":"'${projectName}'","platform":"IOS"},"type":"bundleIds"}}' | jq .)" | jq --raw-output .data.id)
                echo "bundleId=${bundleId}"

                devicesArray=$(curl --silent --request GET "https://api.appstoreconnect.apple.com/v1/devices" --header "Authorization: Bearer ${appStoreConnectAuthorizationBearer}" --header "accept: application/json" | jq '[ .data[] | { id: .id, type: .type } ]')
                echo "devicesArray=${devicesArray}"

                certificateId="$(cat ${signingDir}/Certificate.id)"
                echo "certificateId=${certificateId}"

                data=$(echo '{"data":{"attributes":{"name":"'${projectName}'","profileType":"IOS_APP_ADHOC"},"relationships":{"bundleId":{"data":{"id":"'${bundleId}'","type":"bundleIds"}},"certificates":{"data":[{"id":"'${certificateId}'","type":"certificates"}]},"devices":{"data":[{"id":"id","type":"type"}]}},"type":"profiles"}}' | jq --argjson devicesArray "${devicesArray}" '(.data.relationships.devices.data = $devicesArray)')
                echo "data=${data}"
                
                provisioningProfileContent=$(curl --silent --show-error --fail-with-body --request POST "https://api.appstoreconnect.apple.com/v1/profiles" --header "Authorization: Bearer ${appStoreConnectAuthorizationBearer}" --header "Content-Type: application/json" --header "accept: application/json" --data "${data}" | jq --raw-output .data.attributes.profileContent)
                echo ${provisioningProfileContent} | base64 --decode >> ${signingDir}/App.mobileprovision
        fi

        export certificateEncoded=$(base64 --wrap=0 ${signingDir}/Certificate.p12)
        # echo "certificateEncoded=${certificateEncoded}"

        export provisioningProfileEncoded=$(base64 --wrap=0 ${signingDir}/App.mobileprovision)
        # echo "provisioningProfileEncoded=${provisioningProfileEncoded}"

        export certificatePassword=${IOS_CERTIFICATE_PASSWORD}
fi

## AppCenter
startAppCenterBuild() {
        appCenterRepoName="${repoName}-${1}"
        echo "appCenterRepoName=${appCenterRepoName}"

        appExists=0
        appcenter apps show --app "${APPCENTER_OWNER}/${appCenterRepoName}" > /dev/null || appExists=$?
        echo "appExists=${appExists}"
        if [ ${appExists} != 0 ] ; then
                appcenter orgs apps create --platform "React-Native" --os "${1}" --app-name "${appCenterRepoName}" --display-name "${appCenterRepoName}" --org-name "${APPCENTER_OWNER}"
                sleep 5
        fi

        repoConfigsLength=$( curl --silent --show-error --fail-with-body --request GET "https://api.appcenter.ms/v0.1/apps/${APPCENTER_OWNER}/${appCenterRepoName}/repo_config?includeInactive=false" --header "accept: application/json" --header  "X-API-Token: ${APPCENTER_API_KEY}" | jq length )
        echo "repoConfigsLength=${repoConfigsLength}"
        if [ ${repoConfigsLength} = 0 ] ; then
                repoUrl="https://github.com/${GITHUB_OWNER}/${repoName}.git"
                echo "repoUrl=${repoUrl}"

                curl --silent --show-error --fail-with-body --request POST "https://api.appcenter.ms/v0.1/apps/${APPCENTER_OWNER}/${appCenterRepoName}/repo_config" --header "accept: application/json" --header "X-API-Token: ${APPCENTER_API_KEY}" --header "Content-Type: application/json" --data "{  \"repo_url\": \"${repoUrl}\"}"
                sleep 5
        fi

        ## Remove config if it exists
        if [ "${REBUILD_IOS_PROFILE}" = true ] && [ ${1} = "iOS" ] ; then
                curl --fail-with-body --silent --show-error --request DELETE "https://api.appcenter.ms/v0.1/apps/${APPCENTER_OWNER}/${appCenterRepoName}/branches/main/config" --header "accept: application/json" --header  "X-API-Token: ${APPCENTER_API_KEY}"  || true
        fi

        branchesConfigResponseCode=$( curl --silent --write-out '%{http_code}' --output /dev/null --request GET "https://api.appcenter.ms/v0.1/apps/${APPCENTER_OWNER}/${appCenterRepoName}/branches/main/config" --header "accept: application/json" --header  "X-API-Token: ${APPCENTER_API_KEY}" )
        echo "branchesConfigResponseCode=${branchesConfigResponseCode}"
        if [[ "${branchesConfigResponseCode}" != "200" ]] ; then
                envsubst < "./appcenterBrancheConfigTemplate-${1}.json" > "./appcenterBrancheConfig-${1}.json"
                # cat appcenterBrancheConfig-${1}.json

                # curl --fail-with-body  --show-error --request POST "https://api.appcenter.ms/v0.1/apps/${APPCENTER_OWNER}/${appCenterRepoName}/branches/main/config" --header "accept: application/json" --header "X-API-Token: ${APPCENTER_API_KEY}" --header "Content-Type: application/json" --data-binary "@./appcenterBrancheConfig-${1}.json"
                curl --fail-with-body --output /dev/null  --silent --show-error --request POST "https://api.appcenter.ms/v0.1/apps/${APPCENTER_OWNER}/${appCenterRepoName}/branches/main/config" --header "accept: application/json" --header "X-API-Token: ${APPCENTER_API_KEY}" --header "Content-Type: application/json" --data-binary "@./appcenterBrancheConfig-${1}.json"
                echo "Created AppCenter branche config"
                sleep 5
        fi

        appCenterBuildResponse=$(curl --silent --show-error --fail-with-body --request POST "https://api.appcenter.ms/v0.1/apps/${APPCENTER_OWNER}/${appCenterRepoName}/branches/main/builds" --header "accept: application/json" --header "X-API-Token: ${APPCENTER_API_KEY}" --header "Content-Type: application/json")
        appCenterBuildId=$( echo ${appCenterBuildResponse} | jq --raw-output '.id')
        echo "appCenterBuildId=${appCenterBuildId}"

        appCenterBuildIds[${appCenterRepoName}]=${appCenterBuildId}
}


startAppCenterBuild "iOS"
startAppCenterBuild "Android"                    

while [ ${#appCenterBuildIds[@]} != 0 ]; do
        sleep 5
        for appCenterRepoName in "${!appCenterBuildIds[@]}"; do
                # Do not fail on http error, just try again later
                appCenterBuildResponseExitCode=0
                appCenterBuildResponse=$(curl --silent --show-error --request GET "https://api.appcenter.ms/v0.1/apps/${APPCENTER_OWNER}/${appCenterRepoName}/builds/${appCenterBuildIds[${appCenterRepoName}]}" --header "accept: application/json" --header "X-API-Token: ${APPCENTER_API_KEY}" --header "Content-Type: application/json") || appCenterBuildResponseExitCode=$?
                if [ "${appCenterBuildResponseExitCode}" != 0 ] ; then
                        continue
                fi
                
                appcenterBuildStatus=$( echo ${appCenterBuildResponse} | jq --raw-output '.status')
                appcenterBuildResult=$( echo ${appCenterBuildResponse} | jq --raw-output '.result')
                echo "appCenterRepoName=${appCenterRepoName}"
                
                echo "appcenterBuildStatus=${appcenterBuildStatus}"
                # notStarted
                # inProgress
                # cancelling
                
                echo "appcenterBuildResult=${appcenterBuildResult}"

                if [ "${appcenterBuildStatus}" = "completed" ] ; then
                        if [ "${appcenterBuildResult}" = "failed" ] || [ "${appcenterBuildResult}" = "canceled" ] ; then
                                exitcode=1
                        else
                                # Get groups
                                # curl --request GET "https://api.appcenter.ms/v0.1/apps/${APPCENTER_OWNER}/${appCenterRepoName}/distribution_groups" --header "accept: application/json" --header  "X-API-Token: ${APPCENTER_API_KEY}"

                                # Distribute
                                curl --silent --show-error --fail-with-body --request POST "https://api.appcenter.ms/v0.1/apps/${APPCENTER_OWNER}/${appCenterRepoName}/builds/${appCenterBuildIds[${appCenterRepoName}]}/distribute" --header "accept: application/json" --header "X-API-Token: ${APPCENTER_API_KEY}" --header "Content-Type: application/json" --data-binary "@./distributeInfo.json"
                                echo "Distribute ${appCenterRepoName} finished"
                        fi

                        unset appCenterBuildIds[${appCenterRepoName}]
                fi

                echo ""
        done
done

echo "exitcode=${exitcode}"
exit ${exitcode}