#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <atomic>
#include <cerrno>
#include <cstddef>
#include <cstring>
#include <iostream>
#include <thread>

namespace {
constexpr int kControlHostPort = 17890;
constexpr int kAudioHostPort = 17891;
constexpr char kControlSocketName[] = "wsa_bt_bridge";
constexpr char kAudioSocketName[] = "wsa_bt_audio";

int connect_host(int port) {
    int fd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
        ::close(fd);
        return -1;
    }
    return fd;
}

int create_local_server(const char* socket_name) {
    int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    addr.sun_path[0] = '\0';

    const size_t name_len = std::strlen(socket_name);
    if (name_len + 1 >= sizeof(addr.sun_path)) {
        ::close(fd);
        errno = ENAMETOOLONG;
        return -1;
    }

    std::memcpy(addr.sun_path + 1, socket_name, name_len);
    const socklen_t len = static_cast<socklen_t>(
        offsetof(sockaddr_un, sun_path) + 1 + name_len);

    if (::bind(fd, reinterpret_cast<sockaddr*>(&addr), len) != 0) {
        ::close(fd);
        return -1;
    }

    if (::listen(fd, 8) != 0) {
        ::close(fd);
        return -1;
    }
    return fd;
}

void pump(int from, int to, std::atomic_bool& stop) {
    char buffer[32768];

    while (!stop.load()) {
        const ssize_t n = ::read(from, buffer, sizeof(buffer));
        if (n <= 0) break;

        ssize_t written = 0;
        while (written < n) {
            const ssize_t m = ::write(to, buffer + written,
                                      static_cast<size_t>(n - written));
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

void serve_client(int local_fd, int host_port, const char* label) {
    const int host_fd = connect_host(host_port);
    if (host_fd < 0) {
        std::cerr << "wsa-btd: unable to connect " << label
                  << " to Windows host on 127.0.0.1:" << host_port
                  << ": " << std::strerror(errno) << "\n";
        return;
    }

    std::cerr << "wsa-btd: " << label
              << " client connected; host link established\n";

    std::atomic_bool stop{false};
    std::thread upstream([&] { pump(local_fd, host_fd, stop); });
    std::thread downstream([&] { pump(host_fd, local_fd, stop); });

    upstream.join();
    downstream.join();
    ::close(host_fd);

    std::cerr << "wsa-btd: " << label << " session closed\n";
}

void run_server(const char* socket_name, int host_port, const char* label) {
    const int server_fd = create_local_server(socket_name);
    if (server_fd < 0) {
        std::cerr << "wsa-btd: failed to create abstract socket @"
                  << socket_name << ": " << std::strerror(errno) << "\n";
        return;
    }

    std::cerr << "wsa-btd: " << label << " ready on abstract socket @"
              << socket_name << " -> 127.0.0.1:" << host_port << "\n";

    while (true) {
        const int client_fd = ::accept(server_fd, nullptr, nullptr);
        if (client_fd < 0) {
            if (errno == EINTR) continue;
            std::cerr << "wsa-btd: " << label
                      << " accept failed: " << std::strerror(errno) << "\n";
            break;
        }

        std::thread([client_fd, host_port, label] {
            serve_client(client_fd, host_port, label);
            ::close(client_fd);
        }).detach();
    }

    ::close(server_fd);
}
}  // namespace

int main() {
    std::thread control([] {
        run_server(kControlSocketName, kControlHostPort, "control");
    });

    std::thread audio([] {
        run_server(kAudioSocketName, kAudioHostPort, "audio");
    });

    control.join();
    audio.join();
    return 0;
}
