/* Blocks in a plain C program: global and stack blocks, copying to the
 * heap, __block variables shared between copies, nested blocks. */
#include <stdio.h>
#include <stdlib.h>
#include <Block.h>

typedef int (^IntBlock)(int);

static IntBlock make_adder(int n)
{
    return Block_copy(^(int x) { return x + n; });
}

static void (^make_counter(void))(void)
{
    __block int count = 0;
    void (^b)(void) = ^{ count++; printf("count %d\n", count); };
    void (^heap)(void) = Block_copy(b);
    b();        /* the stack block and the heap copy share count */
    return heap;
}

static int apply(IntBlock f, int x) { return f(x); }

int main(void)
{
    IntBlock twice = ^(int x) { return x * 2; };
    printf("global %d\n", twice(21));
    IntBlock copy = Block_copy(twice);
    printf("global copy same: %d\n", copy == twice);
    Block_release(copy);

    IntBlock add5 = make_adder(5), add10 = make_adder(10);
    printf("adders %d %d\n", add5(1), add10(1));
    IntBlock again = Block_copy(add5);
    printf("heap copy same: %d\n", again == add5);
    Block_release(again);
    Block_release(add5);
    Block_release(add10);

    void (^counter)(void) = make_counter();
    counter();
    counter();
    Block_release(counter);

    __block int total = 0;
    int nums[] = {3, 1, 4, 1, 5};
    for (int i = 0; i < 5; i++) {
        int k = nums[i];
        total += apply(^(int x) { return x * k; }, 2);
    }
    printf("total %d\n", total);

    char *label = "outer";
    IntBlock nested = Block_copy(^(int x) {
        IntBlock inner = ^(int y) { printf("%s %d\n", label, y); return y + 1; };
        return apply(inner, x) * 10;
    });
    printf("nested %d\n", nested(4));
    Block_release(nested);

    /* atexit_b: blocks run at exit, the last added first */
    __block int order = 0;
    for (int i = 1; i <= 2; i++)
        atexit_b(^{ printf("exit block %d ran %s\n", i, order++ == 2 - i ? "in order" : "out of order"); });
    return 0;
}
