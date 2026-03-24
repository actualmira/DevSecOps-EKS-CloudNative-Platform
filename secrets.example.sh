kubectl create secret generic mariadb-secret \
  --from-literal=root-password=YOUR_ROOT_PASSWORD \
  --from-literal=db-user=YOUR_DB_USER \
  --from-literal=db-password=YOUR_DB_PASSWORD \
  --from-literal=healthcheck-password=YOUR_HEALTHCHECK_USER_PWD \
  --namespace <the_namespace>
