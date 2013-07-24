#!/bin/bash
#0.1
#OHIDS REPORTING ENGINE
#Tom Webb

WORKINGDIR=$(/bin/mktemp -d)
DATE=`date -d "-0 day" +%F`
cd $WORKINGDIR
DB_USER=client
DB_NAME=OHIDS
PC_ID=$3
if [ $# -eq 0 ]; then
        echo
        echo "Usage: $0 -t type "
        echo ""
        echo "By Default the TEMP table will be used for mot recent data"
        echo "Common reports:"
        echo "-t Proc_Odd Get processes that are odd. Also has AV  hash results"
        echo "-t Proc_Loc Get processes run from temp directories."
        echo "-t Proc_Diff Shows new Processes running different from previous day"
        echo "-t Proc_Date Shows Files running that have a modified or create date in that last 48 hours"
        echo "-t Start_Diff New items in Computers startup list from the previous day"
        echo "-t Start_Loc shows process in startup in temp directories"
        echo "-t Service_Diff new services on Computers compared to previous day"
        echo "-t Hash_Comp compare hashs of exe to version numbers"
        echo "-t Firewall_Diff Shows firewall changes between different days"
        echo "-t SSN_Top will display top 25 highest SSN Count per Computer"
        echo "-t SSN_Comp will display the top 50 file for a give PC_ID"
        exit
fi

case $1 in
#-t) type=$2; shift 2;;
-t) type=$2;
esac



query_proc_loc()
{
echo "select DISTINCT PC_Id,Proc_File from Process_Temp where Proc_File not like '%Program Files%' and  Proc_File not like '%system32%' and Proc_File not like '%sysWow64%' and Proc_File not like '%windows%' and Proc_File not like '%PROGRA%' and Proc_File not like '%Google% and Proc_File not like in (select DISTINCT Name from Good_File)';" >sql.statement

mysql -u $DB_USER $DB_NAME < sql.statement | sed 's/\t/","/g;s/^/"/;s/$/"/;s/\n//g'> results.csv

cat results.csv
}


query_proc_odd()
{
echo "select DISTINCT PC_Id,Proc_File from Process_Temp where Proc_File like '%recyler%' or  Proc_File like '%system volume information%' or Proc_File like '%temp%' or Proc_File like '%tmp%' and Proc_File not in (select DISTINCT Name from Good_File);" >sql.statement

mysql  -u $DB_USER $DB_NAME < sql.statement | sed 's/\t/","/g;s/^/"/;s/$/"/;s/\n//g' > results.csv

while  IFS=',' read ID File
do
        echo "select PC_Id,File_Name,MD5 from PC_Hash_Temp where PC_Id=$ID and File_Name=$File;" >hash.sql
        mysql --skip-column-names -u $DB_USER $DB_NAME  < hash.sql  | sed 's/\t/,/g;s/\n//g' >> hash.csv
done <results.csv


#Prep file for bulk load
echo "begin" >mal-hash
cut -d ',' -f3 hash.csv |sort |uniq >>mal-hash #TRIM DOWN TO UNIQ RESULTS TO PLAY NICE
echo "end" >>mal-hash
netcat hash.cymru.com 43 <mal-hash >malhash-result
grep -v '#' malhash-result >mal-filtered

while  IFS=',' read  ID File Hash
do
 av_result=`grep -m1 $Hash mal-filtered`
 echo $ID $File $av_result >>final
done <hash.csv

cat final

}

query_start_diff()
{
#determine last PCID
mysql -B --skip-column-names -u $DB_USER $DB_NAME -e "SELECT DISTINCT PC_Id from Start_List_Temp;" >pcid #Get PC_Ids from previous day PC's

while read i
do  #FOR Each PC GET A DIFF

mysql  -B -u $DB_USER $DB_NAME -e "SELECT PC_Info.PC_Id, Cname ,Command from Start_List_Temp, PC_Info where PC_Info.PC_Id=$i and PC_Info.PC_Id = Start_List_Temp.PC_Id and PC_Info.Last_Seen != PC_Info.First_Seen and Command not in (select DISTINCT Command from Start_List where PC_ID=$i);"

done<pcid
}

query_service_diff()
{
mysql -B --skip-column-names -u $DB_USER $DB_NAME -e "SELECT DISTINCT PC_Id from Service_Temp;" >pcid #Get PC_Ids from previous day PC's
while read i
  do  #FOR Each PC GET A DIFF

mysql -B -u $DB_USER $DB_NAME  -e "SELECT PC_Info.PC_Id, Cname ,Name from Service_List_Temp, PC_Info where PC_Info.PC_Id=$i and PC_Info.PC_Id = Service_List_Temp.PC_Id and PC_Info.Last_Seen != PC_Info.First_Seen and Name not in (select DISTINCT Name from Service_List where PC_ID=$i)";
done<pcid
}


query_proc_diff()
{
mysql -B --skip-column-names -u $DB_USER $DB_NAME -e "SELECT DISTINCT PC_Id from Process_Temp;" >pcid #Get PC_Ids from previous day PC's
while read i
 do
mysql -B -u $DB_USER $DB_NAME  -e "SELECT DISTINCT PC_Id, Proc_File from Process where PC_Id=$i and Proc_File not in (select DISTINCT Proc_File from Process_Temp where PC_ID=$i);"
done<pcid
}


query_proc_date()
{
qdate=`date -d "2 day ago" +%Y-%m-%d`
mysql -B -u $DB_USER $DB_NAME -e "SELECT PC_Id, File_Name,MD5 FROM PC_Hash_Temp where CDATE >='$qdate 00:00:00'OR MDATE >='$qdate 00:00:00' order by MD5;"

}

query_start_loc()
{
mysql -B -u $DB_USER $DB_NAME -e "select DISTINCT PC_Id,Command from Start_List_Temp where Command not like '%Program Files%' and Command not like '%/AppData/Local/Google%' and  Command not like '%system32%' and Command not like '%sysWow64%' and Command not like '%windows%' and Command not like '%PROGRA%' and Command not in (select DISTINCT Name from Good_File);"
}

query_hash_comp()
{
#C:/WINDOWS/SYSTEM32/NLSLEXICONS0011.DLL 6.1.7600.16385 (win7_rtm.090713-1255)   f95bef6d4afb35cacb8daf5ff1df8769

mysql -B -u $DB_USER $DB_NAME -e "select File_Name,Version,MD5 from PC_Hash" >hash

cat hash |awk -F '/' '{ print $NF}'|sort |uniq >hash.sort

IFS=`printf '\n\t'`
while read file ver hash ; do

count=`awk '{ if ($1 == "'$file'" && $2 == "'$ver'" ) print $0}' hash.sort |wc -l`

if [ $count -gt 1 ];
 then
   echo $file $ver $hash
fi

done<hash.sort

}

query_firewall_diff()
{
mysql -B --skip-column-names -u $DB_USER $DB_NAME -e "SELECT DISTINCT PC_Id from Firewall_Temp;" >pcid #Get PC_Ids from previous day PC's
while read i
do
 mysql -B -u $DB_USER $DB_NAME  -e "SELECT PC_Info.PC_Id, Cname ,Prog_Path from Firewall_Temp, PC_Info where PC_Info.PC_Id=$i and PC_Info.PC_Id = Firewall_Temp.PC_Id and PC_Info.Last_Seen != PC_Info.First_Seen and Prog_Path not in (select DISTINCT Prog_Path from Firewall where PC_ID=$i)";
done<pcid
}

query_top_ssn()
{

mysql -B -u $DB_USER $DB_NAME  -e  "select Find_SSN.Date,Find_SSN.PC_Id,PC_Info.Cname, SUM(count) as Total, PC_Info.IP FROM Find_SSN, PC_Info where PC_Info.PC_ID=Find_SSN.PC_Id and Find_SSN.Date >= DATE_SUB(NOW(), INTERVAL 14 DAY ) GROUP by PC_ID order by total desc limit 25;"

}

query_ssn_comp()
{
#PC_ID from Global $3

if [ -z $PC_ID ]; then #IF PC_ID is blank
 echo "Please enter a PC_Id"
fi

mysql -B -u $DB_USER $DB_NAME  -e  "select Count, File from Find_SSN where PC_Id=\"$PC_ID\" and count > 50 order by count DESC;"

}


clean ()
{
rm -rf $WORKINGDIR
}


##################################
#Determine QUERY
##################################
if [ $type  = "Proc_Loc" ]; then #Process locaion lookup
query_proc_loc
fi

if [ $type = "Proc_Odd" ]; then
query_proc_odd
fi
if [ $type = "Start_Diff" ]; then
query_start_diff
fi
if [ $type = "Service_Diff" ]; then
query_service_diff
fi

if [ $type = "Proc_Diff" ]; then
query_proc_diff
fi

if [ $type = "Proc_Date" ]; then
query_proc_date
fi

if [ $type = "Start_Loc" ]; then
query_start_loc
fi
if [ $type = "Hash_Comp" ]; then
query_hash_comp
fi

if [ $type = "Firewall_Diff" ]; then
query_firewall_diff
fi

if [ $type = "SSN_Top" ]; then
query_top_ssn
fi

if [ $type = "SSN_Comp" ]; then
query_ssn_comp
fi



clean
