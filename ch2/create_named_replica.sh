# Create logical server
az sql server create -g resourcegroupname -n replicaervername -l region --admin-user adminaccount --admin-password <enter-your-password-here>

# Create named replica for primary database
az sql db replica create -g resourcegroupname -n primarydatabasename -s primaryservername --secondary-type named --partner-database namereplicadatabasename --partner-server replicaervername
