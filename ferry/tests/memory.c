/* Ferry test: memory, sorting, numbers and strings. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

static int by_value(const void *a, const void *b) { return *(const int *)a - *(const int *)b; }

int main(void)
{
    int values[] = {42, 7, 19, 3, 88, 21};
    qsort(values, 6, sizeof values[0], by_value);
    printf("sorted:");
    for (int i = 0; i < 6; i++)
        printf(" %d", values[i]);
    printf("\n");
    int key = 21;
    int *found = bsearch(&key, values, 6, sizeof values[0], by_value);
    printf("found at %ld\n", found ? (long)(found - values) : -1L);

    char *s = malloc(4);
    strcpy(s, "abc");
    s = realloc(s, 64);
    strlcat(s, "defghij", 64);
    printf("realloc kept '%s' size>=64 %d\n", s, malloc_size(s) >= 64);
    free(s);

    char buf[32];
    snprintf(buf, sizeof buf, "%05.1f|%-4s|%x", 3.14159, "ab", 255);
    printf("format '%s'\n", buf);
    char *end;
    printf("strtol %ld rest '%s'\n", strtol("1234xyz", &end, 10), end);
    printf("strtod %.2f\n", strtod("2.5e2", NULL));

    char *map = mmap(NULL, 8192, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (map == MAP_FAILED) {
        perror("mmap");
        return 1;
    }
    memset(map, 'z', 8192);
    printf("mmap ok last=%c\n", map[8191]);
    munmap(map, 8192);

    char text[] = "boats,tides,,harbors";
    char *rest = text, *tok;
    printf("strsep:");
    while ((tok = strsep(&rest, ",")))
        printf(" [%s]", tok);
    printf("\n");
    return 0;
}
