#/bin/bash
#Version 0.1
SQLUSER=""
SQLPASSWD=""

#if [[ $EUID -ne 0 ]]; then
#   echo "This script must be run as root" 1>&2
#   exit 1
#fi

error_check()
{
if (( $? == 0 )); then
    echo "::::::$1 was successful::::::::"
else
    echo "::::::$1 failed::::::"
        exit 1
fi
}

clear
echo "user ID od MYSQL admin user (Normally Root)"
read SQLUSER

echo "Password for MYSQL User"
read -s SQLPASSWD


if [ -z $SQLUSER ]; then #blank
echo "Blank Username"
exit 1

fi

if [ -z $SQLPASSWD ]; then

echo "Password is blank"
exit 1

fi


until mysql -u root -p$SQLPASSWD  -e ";" ; do
       read -p "Can't connect, please retry: " SQLPASSWD
done


mysql -u $SQLUSER -p$SQLPASSWD -e "CREATE DATABASE IF NOT EXISTS OHIDS;" 2>/dev/null
error_check "Database create "
mysql -u $SQLUSER -p$SQLPASSWD OHIDS < schema.db 2>/dev/null
error_check "Database Schema Import"


create_key ()
{
cd /etc/mysql

#Check for files
if [ -e ca-key.pem ]; then echo "ca-key.pem already exists" &&  exit 1; fi
if [ -e server-key.pem  ]; then echo "server-key.pem   already exists" &&  exit 1; fi
if [ -e server-req.pem ]; then echo "server-req.pem  already exists" &&  exit 1; fi
if [ -e server-cert.pem ]; then echo "server-cert.pem  already exists" &&  exit 1; fi
if [ -e client-key.pem ]; then echo "client-key.pem  already exists" &&  exit 1; fi
if [ -e client-req.pem ]; then echo "client-req.pem  already exists" &&  exit 1; fi
if [ -e client-cert.pem ]; then echo "client-cert.pm  already exists" &&  exit 1; fi



openssl genrsa 2048 > ca-key.pem
openssl req -new -x509 -nodes -days 3600 -key ca-key.pem -out ca-cert.pem
openssl req -newkey rsa:2048 -days 3600 -nodes -keyout server-key.pem -out server-req.pem
openssl rsa -in server-key.pem -out server-key.pem
openssl x509 -req -in server-req.pem -days 3600 -CA ca-cert.pem -CAkey ca-key.pem -set_serial 01 -out server-cert.pem


openssl req -newkey rsa:2048 -days 3600  -nodes -keyout client-key.pem -out client-req.pem
openssl rsa -in client-key.pem -out client-key.pem
openssl x509 -req -in client-req.pem -days 3600 -CA ca-cert.pem -CAkey ca-key.pem -set_serial 01 -out client-cert.pem



echo "######################## RESULTS ######################################"
openssl verify -CAfile ca-cert.pem server-cert.pem client-cert.pem

echo "#######################################################################"
chmod 400 *.pem
chown mysql *.pem

}


create_client_user()
{
#create database user
echo
echo
echo "What is the username you want to use for your client MYSQL connection"
read client

echo "What password do you want to use for the mysql user $client"
read -s clientpass

echo "CREATE USER '$client'@'%';" >>createuser.mysql
echo "SET PASSWORD FOR 'external'@'%' = PASSWORD('$clientpass');" >>createuser.mysql
echo "GRANT Insert ON OHIDS.Find_SSN_Temp TO 'external'@'%' REQUIRE SSL;"  >>createuser.mysql
echo "GRANT Insert ON OHIDS.Firewall_Temp TO 'external'@'%'  REQUIRE SSL;"  >>createuser.mysql
echo "GRANT Insert ON OHIDS.Netstat_Temp TO 'external'@'%'  REQUIRE SSL;" >>createuser.mysql
echo "GRANT Insert ON OHIDS.PC_Hash_Temp TO 'external'@'%'  REQUIRE SSL;"  >>createuser.mysql
echo "GRANT Insert ON OHIDS.Process_Temp TO 'external'@'%'  REQUIRE SSL;"  >>createuser.mysql
echo "GRANT Insert ON OHIDS.Sch_Tasks_Temp TO 'external'@'%' REQUIRE SSL;"  >>createuser.mysql
echo "GRANT Insert ON OHIDS.Service_List_Temp TO 'external'@'%'  REQUIRE SSL;" >>createuser.mysql
echo "GRANT Insert ON OHIDS.Start_List_Temp TO 'external'@'%' IDENTIFIED BY 'external' REQUIRE SSL;"  >>createuser.mysql
echo "GRANT Insert ON OHIDS.Error_Log TO 'external'@'%' REQUIRE SSL;" >>createuser.mysql
echo "GRANT EXECUTE ON PROCEDURE OHIDS.get_com_id TO 'external'@'%';"  >>createuser.mysql
echo "GRANT EXECUTE ON PROCEDURE OHIDS.update_comp_info TO 'external'@'%';"  >>createuser.mysql
echo "FLUSH PRIVILEGES;" >>createuser.mysql

mysql -u $SQLUSER -p$SQLPASSWD OHIDS <createuser.mysql

error_check "MYSQL create user"
rm createuser.mysql
}

create_OHIDS_admin()
{

echo "Do you want to create a seperate admin for the OHIDS database? Y or N (Recommended)"
read makeadmin

if [[ ( $makeadmin == "Y" ) || ( $makeadmin == "y" ) ]]; then

echo "What password do you want for the OHIDS users"
read -s ohidspass


echo
echo "Creating user OHIDS@localhost"
echo "create user 'ohids'@'localhost';" >>admin.sql
echo "set password for 'ohids'@'localhost' = PASSWORD('$ohidspass');" >>admin.sql
echo "GRANT All on OHIDS.* to 'slapc'@'localhost' REQUIRE SSL;"  >>admin.sql
echo "FLUSH PRIVILEGES;"  >>admin.sql
mysql -u $SQLUSER -p$SQLPASSWD OHIDS <admin.mysql
error_check "Create OHIDS admin users"

fi
}


echo
echo "Do you want to Create SSL KEYS in /etc/mysql (Y or N)"
read key

if [[ ( $key == "Y" ) || ( $key == "y" )  ]]; then
        create_key
else
        echo
        echo "  create you key manually using http://dev.mysql.com/doc/refman/5.0/en/creating-ssl-certs.html"
        echo
        echo

fi

create_client_user

create_OHIDS_admin
