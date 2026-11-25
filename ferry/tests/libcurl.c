/* A Mac's libcurl, served by this system's (freemac 1.232, Ferry 0.56.0),
 * as OBS uses it: the version, an easy handle, a refused connection and
 * its message. */
#include <curl/curl.h>
#include <stdio.h>

int main(void)
{
    curl_global_init(CURL_GLOBAL_DEFAULT);
    curl_version_info_data *v = curl_version_info(CURLVERSION_NOW);
    printf("libcurl %d, with TLS %d\n", (int)(v->version_num >> 16), v->ssl_version != NULL);
    CURL *c = curl_easy_init();
    curl_easy_setopt(c, CURLOPT_URL, "http://127.0.0.1:1/");
    curl_easy_setopt(c, CURLOPT_CONNECTTIMEOUT, 5L);
    curl_easy_setopt(c, CURLOPT_NOPROXY, "*");
    CURLcode r = curl_easy_perform(c);
    printf("refused %d: %s\n", r == CURLE_COULDNT_CONNECT, curl_easy_strerror(r));
    struct curl_slist *h = curl_slist_append(NULL, "Accept: application/json");
    h = curl_slist_append(h, "X-Ferry: 1");
    printf("headers %s, %s\n", h->data, h->next->data);
    curl_slist_free_all(h);
    curl_easy_cleanup(c);
    curl_global_cleanup();
    return 0;
}
