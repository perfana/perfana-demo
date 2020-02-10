#!/bin/bash
docker exec -ti perfana-test-env_keycloak_1 /opt/jboss/keycloak/bin/standalone.sh \
	-Djboss.socket.binding.port-offset=1000 \
	-Dkeycloak.migration.action=export \
	-Dkeycloak.migration.provider=singleFile \
	-Dkeycloak.migration.realmName=perfana \
	-Dkeycloak.migration.usersExportStrategy=REALM_FILE  \
	-Dkeycloak.migration.file=/tmp/keycloak/keycloak-perfana-realm.json
