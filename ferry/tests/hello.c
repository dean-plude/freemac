/* Ferry test: printing, arguments, environment, exit status. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    printf("hello from a Mac program\n");
    puts("puts works");
    fprintf(stdout, "argc=%d first=%s\n", argc, argc > 1 ? argv[1] : "(none)");
    fprintf(stderr, "this line goes to stderr\n");
    const char *v = getenv("FERRY_TEST_VALUE");
    printf("env=%s\n", v ? v : "(unset)");
    fputs("done\n", stdout);
    return 3;
}
