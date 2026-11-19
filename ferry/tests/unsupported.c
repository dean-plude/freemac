/* Ferry test: a call Ferry doesn't have stops the program with a message. */
#include <stdio.h>

int pthread_yield_np(void); /* not provided by Ferry */

int main(void)
{
    printf("before\n");
    pthread_yield_np();
    printf("after (should not appear)\n");
    return 0;
}
