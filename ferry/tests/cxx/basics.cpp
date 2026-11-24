// SPDX-License-Identifier: GPL-3.0-or-later
// A Mac C++ program on this system's libc++: containers, strings, streams
// (sharing stdout with printf), locales' character classes, stream
// positions, chrono, the file system, operator new and delete, and a
// static object destroyed at exit.
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <locale>
#include <map>
#include <memory>
#include <numeric>
#include <regex>
#include <set>
#include <sstream>
#include <string>
#include <unistd.h>
#include <unordered_map>
#include <vector>

struct Global {
    const char *name;
    explicit Global(const char *n) : name(n) { std::printf("construct %s\n", name); }
    ~Global() { std::printf("destroy %s\n", name); }
};
static Global global("global");

static int news;
void *operator new(std::size_t n)
{
    news++;
    void *p = std::malloc(n ? n : 1);
    if (!p)
        throw std::bad_alloc();
    return p;
}
void operator delete(void *p) noexcept { std::free(p); }
void operator delete(void *p, std::size_t) noexcept { std::free(p); }

int main()
{
    // containers and algorithms
    std::vector<int> v(10);
    std::iota(v.begin(), v.end(), 1);
    std::reverse(v.begin(), v.end());
    std::sort(v.begin(), v.begin() + 5);
    std::cout << "vector";
    for (int x : v)
        std::cout << ' ' << x;
    std::cout << "\nsum " << std::accumulate(v.begin(), v.end(), 0) << '\n';
    std::map<std::string, int> m{{"pear", 3}, {"apple", 1}, {"fig", 2}};
    for (const auto &kv : m)
        std::cout << kv.first << '=' << kv.second << ' ';
    std::cout << '\n';
    std::unordered_map<int, std::string> u;
    for (int i = 0; i < 100; i++)
        u[i] = std::to_string(i * i);
    std::cout << "unordered " << u.size() << ' ' << u[12] << '\n';
    std::set<std::string> s{"b", "a", "c", "a"};
    std::cout << "set " << s.size() << ' ' << *s.begin() << '\n';

    // strings and numbers
    std::string str = "Hello, " + std::string("world");
    str += '!';
    std::cout << str << " length " << str.size() << " find " << str.find("world") << '\n';
    std::cout << "stod " << std::stod("2.5") * 2 << " stoll " << std::stoll("-1234567890123") << '\n';
    std::cout << std::fixed << std::setprecision(3) << 3.14159 << ' ' << std::hex << 255 << std::dec << ' '
              << std::setw(6) << std::setfill('*') << 42 << std::setfill(' ') << '\n';
    std::cout.unsetf(std::ios::fixed);

    // printf and cout in order
    std::printf("printf one\n");
    std::cout << "cout two\n";
    std::printf("printf three\n");
    std::cout << "cout four" << std::endl;

    // character classes, read from the program's own copy of the table
    std::locale loc;
    const std::ctype<char> &ct = std::use_facet<std::ctype<char>>(loc);
    std::string classes;
    for (char c : std::string("a Z9_\t."))
        classes += ct.is(std::ctype_base::alpha, c) ? 'A' : ct.is(std::ctype_base::digit, c) ? 'D'
                 : ct.is(std::ctype_base::space, c) ? 'S' : ct.is(std::ctype_base::punct, c) ? 'P' : '-';
    std::cout << "classes " << classes << " upper " << ct.toupper('q') << ' ' << std::isspace(' ', loc) << '\n';
    std::istringstream words("  the quick\tbrown\n fox ");
    std::string w;
    int count = 0;
    while (words >> w)
        std::cout << (count++ ? "," : "words ") << w;
    std::cout << '\n';
    std::regex re("([a-z]+)@([a-z]+)\\.com");
    std::smatch match;
    std::string mail = "write to someone@example.com today";
    if (std::regex_search(mail, match, re))
        std::cout << "regex " << match[1] << " at " << match[2] << '\n';

    // stream positions
    std::stringstream ss;
    ss << "0123456789";
    ss.seekg(4);
    char c;
    ss >> c;
    std::streampos pos = ss.tellg();
    std::cout << "seekg " << c << " tellg " << pos << " tellp " << ss.tellp() << '\n';

    // functions, smart pointers
    std::function<int(int)> square = [](int x) { return x * x; };
    auto p = std::make_unique<std::vector<int>>(3, 7);
    auto sp = std::make_shared<std::string>("shared");
    std::weak_ptr<std::string> wp = sp;
    std::cout << "function " << square(9) << " unique " << p->size() << ' ' << (*p)[2] << " shared "
              << sp.use_count() << ' ' << *wp.lock() << '\n';
    std::cout << "operator new used " << (news > 0 ? "yes" : "no") << '\n';

    // chrono
    auto t0 = std::chrono::steady_clock::now();
    usleep(2000);
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
    auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    std::cout << "chrono " << (ms >= 2 && ms < 2000 ? "ok" : "wrong") << ' ' << (now > 1600000000 ? "ok" : "wrong")
              << '\n';

    // the file system
    namespace fs = std::filesystem;
    fs::path dir = fs::temp_directory_path() / ("ferry_cxx_basics_" + std::to_string(getpid()));
    fs::create_directories(dir / "sub");
    std::ofstream(dir / "a.txt") << "some text\n";
    std::vector<std::string> names;
    for (const auto &e : fs::directory_iterator(dir))
        names.push_back(e.path().filename().string() + (e.is_directory() ? "/" : ""));
    std::sort(names.begin(), names.end());
    std::cout << "files";
    for (auto &n : names)
        std::cout << ' ' << n;
    std::ifstream in(dir / "a.txt");
    std::string line;
    std::getline(in, line);
    std::cout << " size " << fs::file_size(dir / "a.txt") << " line '" << line << "' ext "
              << fs::path("x/y.tar.gz").extension() << '\n';
    std::error_code ec;
    fs::remove_all(dir, ec);
    std::cout << "removed " << !fs::exists(dir) << " missing " << fs::exists(dir / "nothing") << '\n';
    return 0;
}
