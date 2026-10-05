#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <atomic>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <string>
#include <thread>

namespace {
constexpr int kHostPort = 17890;
constexpr char kSocketName[] = "wsa_bt_bridge";

int connect_host() {
    int fd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(kHostPort);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
        ::close(fd);
        return -1;
    }
    return fd;
}

int create_local_server() {
    int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    addr.sun_path[0] = '\0';
    std::memcpy(addr.sun_path + 1, kSocketName, sizeof(kSocketName) - 1);

    socklen_t len = static_cast<socklen_t>(
        offsetof(sockaddr_un, sun_path) + 1 + sizeof(kSocketName) - 1);

    if (::bind(fd, reinterpret_cast<sockaddr*>(&addr), len) != 0) {
        ::close(fd);
        return -1;
    }
    if (::listen(fd, 4) != 0) {
        ::close(fd);
        return -1;
    }
    return fd;
}

void pump(int from, int to, std::atomic_bool& stop) {
    char buffer[8192];
    while (!stop.load()) {
        const ssize_t n = ::read(from, buffer, sizeof(buffer));
        if (n <= 0) break;

        ssize_t written = 0;
        while (written < n) {
            const ssize_t m = ::write(to, buffer + written, static_cast<size_t>(n - written));
            if (m <= 0) {
                stop.store(true);
                return;
            }
            written += m;
        }
    }
    stop.store(true);
    ::shutdown(to, SHUT_WR);
}

void serve_client(int local_fd) {
    int host_fd = connect_host();
    if (host_fd < 0) {
        std::cerr << "wsa-btd: unable to connect to Windows host on 127.0.0.1:"
                  << kHostPort << ": " << std::strerror(errno) << "\n";
        return;
    }

    std::cerr << "wsa-btd: local framework client connected; host link established\n";
    std::atomic_bool stop{false};

    std::thread upstream([&] { pump(local_fd, host_fd, stop); });
    std::thread downstream([&] { pump(host_fd, local_fd, stop); });

    upstream.join();
    downstream.join();

    ::close(host_fd);
    std::cerr << "wsa-btd: session closed\n";
}
}  // namespace

int main() {
    const int server_fd = create_local_server();
    if (server_fd < 0) {
        std::cerr << "wsa-btd: failed to create abstract socket @" << kSocketName
                  << ": " << std::strerror(errno) << "\n";
        return 1;
    }

    std::cerr << "wsa-btd: ready on abstract socket @" << kSocketName << "\n";

    while (true) {
        int client_fd = ::accept(server_fd, nullptr, nullptr);
        if (client_fd < 0) {
            if (errno == EINTR) continue;
            std::cerr << "wsa-btd: accept failed: " << std::strerror(errno) << "\n";
            break;
        }

        serve_client(client_fd);
        ::close(client_fd);
    }

    ::close(server_fd);
    return 0;
}
