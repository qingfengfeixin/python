#!/bin/bash
# This program configure the enviroment for oracle database(version 11.2.0.4 64bit) on your system
# 2016-03-18 Second release
 
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
 
#variables
service=zf
orapwd=oracle11gRAC
gridpwd=oracle11gASM
 
rac1=node1
rac1priv=node1-priv
rac2=node2
rac2priv=node2-priv
scan=dbcenter
 
cat >> /etc/hosts <<EOF
192.168.93.120  $rac1
192.168.93.121 $rac1-vip
12.0.0.1 $rac1-priv

192.168.93.122  $rac2
192.168.93.123 $rac2-vip
12.0.0.2  $rac2-priv
192.168.93.124   $scan
EOF
 
isdvd=no
function alert() {
        echo -e "$1"
        exit -1
}
 
echo "*******************************************************************"
echo "                     System environment check                      "
neededPackage="smartmontools unzip openssh-clients binutils compat-libstdc++-33 compat-libstdc++-296 elfutils-libelf elfutils-libelf-devel gcc gcc-c++ glibc glibc-common glibc-devel glibc-headers libaio libaio-devel libgcc libstdc++ libstdc++-devel make openmotif sysstat unixODBC unixODBC-devel compat-libcap1"
missing=$(rpm -q $neededPackage| grep "not installed")
 
#test -z "$missing" && echo "package check passed" || alert "${missing} \\n please install the package above then rerun this program"
 
if [ -z "$missing" ]; then
        echo "package check passed"
else
        echo -e "${missing} \\n Please insert the os install Disc or upload the iso."
        echo "Where is your operation system installation media?"
        select media in "dvd Disc" "iso" ;do
        if [ "$media" == "dvd Disc" ] || [ "$media" == "iso" ];  then
        break
        fi;
        done
        echo "You have selected $media"
 
        mkdir /mnt/dvd
        if [ "$media" == "dvd Disc" ]; then
                isdvd=yes
                mount /dev/cdrom /mnt/dvd
        else
                read -p "Where is the iso?(in absolute path,default, /u01/rhel-server-6.4-x86_64-dvd.iso)" isopath
                mount "$isopath" -o loop /mnt/dvd
        fi;
 
        test $? != 0 && alert "Error occured while mounting the media,please check and try again!"
            
        test -d /etc/yum.repos.d/bak && mv -f /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak || mkdir /etc/yum.repos.d/bak
cat >/etc/yum.repos.d/rhel6.repo<<EOF
[dvd]
name=dvd
baseurl=file:///mnt/dvd
enabled=1
gpgcheck=0
EOF
 
        yum install $neededPackage -y
fi
 
groupadd -g 600 oinstall
groupadd -g 601 asmadmin
groupadd -g 602 asmdba
groupadd -g 603 asmoper
groupadd -g 604 dba
groupadd -g 605 oper

useradd -u 600 -g oinstall -G asmadmin,asmdba,asmoper,dba grid
id grid
 
echo "$gridpwd" | passwd grid --stdin
 

useradd -u 601 -g oinstall -G dba,oper,asmdba oracle
id oracle
echo "$orapwd" | passwd oracle --stdin
 
#[ $? != 0 ] && alert "Error occured where create oracle users,please check"
 
echo "Disable the iptables and selinux"
service iptables stop
chkconfig iptables off
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
 
#modify the size of /dev/shm(default is half of physical memory,11g auto memory management need the /dev/shm greater or equal memory_target) 
[ -f /etc/fstab.bak ] || cp /etc/fstab /etc/fstab.bak
[ -f /etc/rc.d/rc.sysinit.bak ] || cp /etc/rc.d/rc.sysinit /etc/rc.d/rc.sysinit.bak
#num=`cat -n /etc/fstab | grep /dev/shm | awk '{ print $1 }'`
tootalMem=`free -m | grep Mem: |sed 's/^Mem:\s*//'| awk '{print $1}'`
[ $tootalMem -lt 1000 ] && alert "The physical memory is ${tootalMem}M,oracle requires at least 1G" || echo "Your physical memory is ${tootalMem} (in MB)"
num=`grep -n /dev/shm /etc/fstab | awk -F: '{ print $1 }'`
declare -i newSize=$tootalMem*80/100+400 #at least plus 10
sed -i "${num}s/defaults.*/defaults,size=${newSize}M     0 0/" /etc/fstab
 
#num=`cat -n /etc/rc.d/rc.sysinit | grep "mount -f /dev/shm" | awk '{ print $1 }'`
num=`grep -n "mount -f /dev/shm" /etc/rc.d/rc.sysinit | awk -F: '{ print $1 }'`
sed -i "${num}s/mount/#mount/" /etc/rc.d/rc.sysinit
mount -o remount tmpfs
test $? != 0 && alert "Error occured while remounting the tmpfs,please check!!!"
sed -i 's/\-t nonfs,nfs4/\-t tmpfs,nonfs,nfs4/' /etc/rc.d/rc.sysinit
 
cat >>/etc/sysctl.conf<<EOF
#required by oracle
kernel.shmmni = 4096
kernel.sem = 250 32000 100 128
#10g is 65536
fs.file-max = 6815744
#10g is 1024 65000
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
#10g is 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
#10g is 262144
net.core.wmem_max = 1048576
#no need by 10g 
fs.aio-max-nr = 1048576
EOF
sysctl -p
 
cat >> /etc/security/limits.conf <<EOF
grid soft nproc 2047
grid hard nproc 16384
grid soft nofile 1024
grid hard nofile 65536
oracle soft nproc 2047
oracle hard nproc 16384
oracle soft nofile 1024
oracle hard nofile 65536
EOF
 
#print
chkconfig cups off
chkconfig hplip off
#selinux
chkconfig mcstrans off
chkconfig setroubleshoot off
#bluetooth
chkconfig hidd off
chkconfig bluetooth off
 
chkconfig ip6tables off
chkconfig iptables off
chkconfig sendmail off
chkconfig yum-updatesd off
 
#check the node number
[ $(hostname | grep 1$) ] && nodenum=1 || nodenum=2 && echo number $nodenum node
 
 
sed -i '10,$d' ~grid/.bash_profile
cat >>~grid/.bash_profile<<EOF
export ORACLE_BASE=/u01/app/grid
export ORACLE_HOME=/u01/app/11.2.0/grid
export ORACLE_SID=+ASM$nodenum
export JAVA_HOME=\$ORACLE_HOME/jdk
 
export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:\$ORACLE_HOME/ctx/lib:\$ORACLE_HOME/oracm/lib
export CLASSPATH=\$ORACLE_HOME/JRE:\$ORACLE_HOME/jlib:\$ORACLE_HOME/rdbms/jlib:\$ORACLE_HOME/network/jlib
 
export PATH=\$PATH:\$ORACLE_HOME/bin
EOF
 
sed -i '10,$d' ~oracle/.bash_profile
cat >>~oracle/.bash_profile<<EOF
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=\$ORACLE_BASE/product/11.2.0/db_1
export ORACLE_SID=$service$nodenum
 
export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:\$ORACLE_HOME/oracm/lib:/lib:/usr/lib:/usr/local/lib
export CLASSPATH=\$ORACLE_HOME/JRE:\$ORACLE_HOME/jlib:\$ORACLE/rdbms/jlib:\$ORACLE_HOME/network/jlib
 
export PATH=\$PATH:\$ORACLE_HOME/bin
EOF
 
mkdir -p /u01/app/oracle
mkdir -p /u01/app/grid
mkdir -p /u01/app/11.2.0/grid
chown -R grid:oinstall /u01/app
chown oracle:oinstall /u01/app/oracle
chown -R grid:oinstall /u01/app/11.2.0/grid
 
[ "$nodenum" == 1 ] && exit
echo "---------------Configure ssh conectivity----------------"
 
cat >/u01/sshUserSetup.sh<<EOF
#!/bin/bash
 
ssh-keygen -f ~/.ssh/id_rsa -N ''
ssh-copy-id $rac1
cp .ssh/id_rsa.pub .ssh/authorized_keys
ssh $rac1 "ssh-keygen -f ~/.ssh/id_rsa -N ''"
ssh $rac1 cat .ssh/id_rsa.pub>>.ssh/authorized_keys
scp .ssh/authorized_keys $rac1:.ssh
ssh $rac1 date;ssh $rac1priv date;ssh $rac2 date;ssh $rac2priv date;
scp .ssh/known_hosts $rac1:.ssh
 
echo -e "Run the following command as the user(you have just executed /u01/sshUserSetup.sh) on rac1 to test ssh conectivity\n ssh $rac1 date;ssh $rac1priv date;ssh $rac2 date;ssh $rac2priv date"
EOF
 
chmod o+x /u01/sshUserSetup.sh
echo  -e "Run the following command as grid and oracle user on rac2 to setup ssh conectivity\n /u01/sshUserSetup.sh"

