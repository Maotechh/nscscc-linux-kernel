/*
 * mikutap-web-server: single-file HTTP static server + SSE matrix-keyboard bridge.
 *
 * Targets:
 *   - NSCSCC experiment box Linux (loongarch32r, static build)
 *   - x86_64 Linux test build
 *
 * Usage:
 *   mikutap-web-server [-p PORT] [-r WWWROOT] [-b BTN_PATH] [-i POLL_MS]
 *
 * Defaults:
 *   port 80, root /www/mikutap,
 *   btn path: /dev/chiplab_confreg offset 0x1024, or a sysfs path.
 *   poll interval 10 ms while SSE clients are connected.
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define MAX_CLIENTS 16
#define RECV_BUF_SIZE 4096
#define SSE_QUEUE_SIZE 16384
#define MAX_PATH 512

struct client {
    int fd;
    int sse;
    int keep_open;
    char recv_buf[RECV_BUF_SIZE];
    size_t recv_len;
    int request_done;
    char *response;
    size_t response_len;
    size_t response_sent;
    unsigned char queue[SSE_QUEUE_SIZE];
    size_t q_head;
    size_t q_len;
    time_t last_keepalive;
};

static struct client clients[MAX_CLIENTS];
static int listen_fd = -1;
static int btn_fd = -1;
static int btn_event_fd = -1;
static int btn_use_events = 0;
static unsigned short prev_keys = 0;
static int active_sse = 0;
static int running = 1;
static int port = 80;
static const char *www_root = "/www/mikutap";
static const char *btn_path =
    "/sys/class/chiplab_confreg/chiplab_confreg/btn_key";
static int poll_ms = 10;
static int btn_is_chardev = 0;
static unsigned long btn_chardev_offset = 0x1024;

static void die(const char *msg) {
    perror(msg);
    exit(1);
}

static void set_nonblock(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) flags = 0;
    (void)fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

static const char *mime_for_path(const char *path) {
    const char *dot = strrchr(path, '.');
    if (!dot) return "application/octet-stream";
    if (!strcmp(dot, ".html") || !strcmp(dot, ".htm"))
        return "text/html; charset=utf-8";
    if (!strcmp(dot, ".js")) return "application/javascript; charset=utf-8";
    if (!strcmp(dot, ".css")) return "text/css; charset=utf-8";
    if (!strcmp(dot, ".json")) return "application/json; charset=utf-8";
    if (!strcmp(dot, ".png")) return "image/png";
    if (!strcmp(dot, ".jpg") || !strcmp(dot, ".jpeg")) return "image/jpeg";
    if (!strcmp(dot, ".gif")) return "image/gif";
    if (!strcmp(dot, ".ico")) return "image/x-icon";
    if (!strcmp(dot, ".svg")) return "image/svg+xml";
    if (!strcmp(dot, ".woff")) return "font/woff";
    if (!strcmp(dot, ".woff2")) return "font/woff2";
    if (!strcmp(dot, ".mp3")) return "audio/mpeg";
    if (!strcmp(dot, ".ogg")) return "audio/ogg";
    if (!strcmp(dot, ".wav")) return "audio/wav";
    if (!strcmp(dot, ".map")) return "application/json; charset=utf-8";
    if (!strcmp(dot, ".txt")) return "text/plain; charset=utf-8";
    return "application/octet-stream";
}

static int path_is_safe(const char *url) {
    const char *p = url;
    if (*p != '/') return 0;
    while (*p) {
        if (p[0] == '.' && p[1] == '.' &&
            (p[2] == '/' || p[2] == '\0'))
            return 0;
        p++;
    }
    return 1;
}

static void free_response(struct client *c) {
    free(c->response);
    c->response = NULL;
    c->response_len = 0;
    c->response_sent = 0;
}

static void close_client(int idx) {
    struct client *c = &clients[idx];
    if (c->fd >= 0) close(c->fd);
    if (c->sse) active_sse--;
    free_response(c);
    memset(c, 0, sizeof(*c));
    c->fd = -1;
}

static int queue_put(struct client *c, const unsigned char *data, size_t len) {
    size_t room = SSE_QUEUE_SIZE - c->q_len;
    if (len > room) return -1;
    for (size_t i = 0; i < len; i++) {
        size_t pos = (c->q_head + c->q_len + i) % SSE_QUEUE_SIZE;
        c->queue[pos] = data[i];
    }
    c->q_len += len;
    return 0;
}

static size_t queue_peek(struct client *c, unsigned char *out, size_t max) {
    size_t n = 0;
    while (n < max && n < c->q_len) {
        out[n] = c->queue[(c->q_head + n) % SSE_QUEUE_SIZE];
        n++;
    }
    return n;
}

static void queue_discard(struct client *c, size_t n) {
    if (n > c->q_len) n = c->q_len;
    c->q_head = (c->q_head + n) % SSE_QUEUE_SIZE;
    c->q_len -= n;
}

static void broadcast_event(int key, int state) {
    char data[96];
    int n = snprintf(data, sizeof(data), "data: {\"key\":%d,\"state\":%d}\n\n",
                     key, state);
    if (n <= 0 || (size_t)n >= sizeof(data)) return;
    for (int i = 0; i < MAX_CLIENTS; i++) {
        struct client *c = &clients[i];
        if (c->fd >= 0 && c->sse) {
            if (queue_put(c, (const unsigned char *)data, (size_t)n) != 0) {
                /* Slow client: drop oldest event, then retry once. */
                queue_discard(c, c->q_len);
                (void)queue_put(c, (const unsigned char *)data, (size_t)n);
            }
        }
    }
}

static int read_button_value(unsigned short *now_keys) {
    if (btn_is_chardev) {
        unsigned int value = 0;
        ssize_t n = pread(btn_fd, &value, sizeof(value),
                          (off_t)btn_chardev_offset);
        if (n == (ssize_t)sizeof(value)) {
            *now_keys = (unsigned short)(value & 0xffff);
            return 0;
        }
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
            return -1;
        /* Broken /dev node; fall back to sysfs after closing. */
        close(btn_fd);
        btn_fd = -1;
        btn_is_chardev = 0;
    }

    char buf[64];
    int need_reopen = 0;

    if (btn_fd < 0) {
        btn_fd = open(btn_path, O_RDONLY);
        if (btn_fd < 0) return -1;
        set_nonblock(btn_fd);
    }

    if (lseek(btn_fd, 0, SEEK_SET) < 0) {
        if (errno == ESPIPE) {
            /* Some sysfs-like files are not seekable; reopen below. */
            need_reopen = 1;
        } else {
            close(btn_fd);
            btn_fd = -1;
            return -1;
        }
    }

    ssize_t n = read(btn_fd, buf, sizeof(buf) - 1);
    if (n <= 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK)
            return -1;
        close(btn_fd);
        btn_fd = -1;
        return -1;
    }
    buf[n] = '\0';

    if (need_reopen) {
        close(btn_fd);
        btn_fd = -1;
    }

    *now_keys = (unsigned short)(strtoul(buf, NULL, 0) & 0xffff);
    return 0;
}

static void poll_button(void) {
    unsigned short now_keys = 0;
    int have = read_button_value(&now_keys);
    if (have < 0) return;
    unsigned short changed = now_keys ^ prev_keys;
    for (int i = 0; i < 16; i++) {
        unsigned short mask = (unsigned short)(1u << i);
        if (!(changed & mask)) continue;
        broadcast_event(i, (now_keys & mask) ? 1 : 0);
    }
    prev_keys = now_keys;
}

static void read_button_events(void) {
    unsigned char buf[128];
    ssize_t n = read(btn_event_fd, buf, sizeof(buf));
    int i;

    if (n <= 0) {
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
            return;
        close(btn_event_fd);
        btn_event_fd = -1;
        btn_use_events = 0;
        return;
    }
    for (i = 0; i + 1 < (int)n; i += 2) {
        int key = buf[i];
        int state = buf[i + 1];
        if (key < 0 || key > 15) continue;
        if (state != 0 && state != 1) continue;
        /* Keep the kernel queue drained when nobody is listening. */
        if (active_sse > 0)
            broadcast_event(key, state);
    }
}

static void prepare_response(struct client *c, const char *method,
                             const char *url) {
    char path[MAX_PATH + 8];
    char header[512];
    char *body = NULL;
    size_t body_len = 0;
    struct stat st;
    FILE *f = NULL;

    if (strcmp(method, "GET") != 0 && strcmp(method, "HEAD") != 0) {
        body = strdup("<html><body>Method Not Allowed</body></html>\n");
        body_len = strlen(body);
        int hl = snprintf(header, sizeof(header),
            "HTTP/1.1 405 Method Not Allowed\r\n"
            "Content-Type: text/plain; charset=utf-8\r\n"
            "Content-Length: %zu\r\n"
            "Connection: close\r\n\r\n", body_len);
        c->response = malloc((size_t)hl + body_len);
        memcpy(c->response, header, (size_t)hl);
        memcpy(c->response + hl, body, body_len);
        c->response_len = (size_t)hl + body_len;
        free(body);
        return;
    }

    if (strcmp(url, "/events") == 0) {
        int hl = snprintf(header, sizeof(header),
            "HTTP/1.1 200 OK\r\n"
            "Content-Type: text/event-stream; charset=utf-8\r\n"
            "Cache-Control: no-cache\r\n"
            "Connection: keep-alive\r\n"
            "Access-Control-Allow-Origin: *\r\n\r\n"
            "retry: 1000\n\n");
        c->response = malloc((size_t)hl);
        memcpy(c->response, header, (size_t)hl);
        c->response_len = (size_t)hl;
        c->sse = 1;
        active_sse++;
        c->keep_open = 1;
        c->last_keepalive = time(NULL);
        return;
    }

    char url_buf[MAX_PATH];
    snprintf(url_buf, sizeof(url_buf), "%s", url);
    if (!path_is_safe(url_buf)) snprintf(url_buf, sizeof(url_buf), "/");
    if (strcmp(url_buf, "/") == 0) snprintf(url_buf, sizeof(url_buf), "/index.html");

    if (snprintf(path, sizeof(path), "%s%s", www_root, url_buf) >=
        (int)sizeof(path)) {
        snprintf(url_buf, sizeof(url_buf), "/404.html");
        snprintf(path, sizeof(path), "%s%s", www_root, url_buf);
    }
    if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) {
        snprintf(path, sizeof(path), "%s/404.html", www_root);
        if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) {
            body = strdup("<html><body>404 Not Found</body></html>\n");
            body_len = strlen(body);
        }
    }

    if (!body) {
        f = fopen(path, "rb");
        if (!f) {
            body = strdup("<html><body>500 Internal Server Error</body></html>\n");
            body_len = strlen(body);
        } else {
            body_len = (size_t)st.st_size;
            body = malloc(body_len ? body_len : 1);
            if (!body || fread(body, 1, body_len, f) != body_len) {
                if (body) free(body);
                body = strdup("<html><body>500 Internal Server Error</body></html>\n");
                body_len = strlen(body);
            }
            fclose(f);
        }
    }

    const char *mime = mime_for_path(strrchr(path, '/') ? path : path);
    int hl = snprintf(header, sizeof(header),
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: %s\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n"
        "Cache-Control: no-cache\r\n\r\n", mime, body_len);
    c->response = malloc((size_t)hl + body_len);
    if (!c->response) {
        free(body);
        return;
    }
    memcpy(c->response, header, (size_t)hl);
    memcpy(c->response + hl, body, body_len);
    c->response_len = (size_t)hl + body_len;
    free(body);
}

static void parse_requests(void) {
    for (int i = 0; i < MAX_CLIENTS; i++) {
        struct client *c = &clients[i];
        if (c->fd < 0 || c->request_done) continue;
        ssize_t n = recv(c->fd, c->recv_buf + c->recv_len,
                         sizeof(c->recv_buf) - 1 - c->recv_len, 0);
        if (n > 0) {
            c->recv_len += (size_t)n;
            c->recv_buf[c->recv_len] = '\0';
            char *end = strstr(c->recv_buf, "\r\n\r\n");
            if (!end) {
                if (c->recv_len >= sizeof(c->recv_buf) - 2) {
                    close_client(i);
                }
                continue;
            }
            *end = '\0';
            c->request_done = 1;
            char *line = c->recv_buf;
            char *sp1 = strchr(line, ' ');
            if (!sp1) {
                close_client(i);
                continue;
            }
            *sp1 = '\0';
            char *url = sp1 + 1;
            char *sp2 = strchr(url, ' ');
            if (sp2) *sp2 = '\0';
            prepare_response(c, line, url);
        } else if (n == 0) {
            close_client(i);
        } else if (errno != EAGAIN && errno != EWOULDBLOCK) {
            close_client(i);
        }
    }
}

static void write_clients(void) {
    for (int i = 0; i < MAX_CLIENTS; i++) {
        struct client *c = &clients[i];
        if (c->fd < 0) continue;

        if (c->response && c->response_sent < c->response_len) {
            size_t left = c->response_len - c->response_sent;
            ssize_t n = send(c->fd, c->response + c->response_sent, left,
                             MSG_NOSIGNAL);
            if (n > 0) {
                c->response_sent += (size_t)n;
            } else if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
                close_client(i);
                continue;
            }
        }

        if (!c->sse) {
            if (c->response_sent >= c->response_len) {
                close_client(i);
                continue;
            }
        }

        if (c->sse) {
            if (c->q_len > 0) {
                unsigned char tmp[1024];
                size_t n = queue_peek(c, tmp, sizeof(tmp));
                ssize_t sent = send(c->fd, tmp, n, MSG_NOSIGNAL);
                if (sent > 0) {
                    queue_discard(c, (size_t)sent);
                } else if (sent < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
                    close_client(i);
                    continue;
                }
            }
            time_t now = time(NULL);
            if (now - c->last_keepalive >= 15) {
                const char *ping = ": ping\n\n";
                if (queue_put(c, (const unsigned char *)ping, strlen(ping)) == 0)
                    c->last_keepalive = now;
            }
        }
    }
}

static void accept_clients(void) {
    for (;;) {
        struct sockaddr_in addr;
        socklen_t alen = sizeof(addr);
        int fd = accept(listen_fd, (struct sockaddr *)&addr, &alen);
        if (fd < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) break;
            if (errno == EINTR) continue;
            break;
        }
        int slot = -1;
        for (int i = 0; i < MAX_CLIENTS; i++) {
            if (clients[i].fd < 0) {
                slot = i;
                break;
            }
        }
        if (slot < 0) {
            close(fd);
            continue;
        }
        set_nonblock(fd);
        memset(&clients[slot], 0, sizeof(clients[slot]));
        clients[slot].fd = fd;
    }
}

static void handle_signal(int sig) {
    (void)sig;
    running = 0;
}

int main(int argc, char **argv) {
    int opt;
    while ((opt = getopt(argc, argv, "p:r:b:i:")) != -1) {
        switch (opt) {
        case 'p': port = atoi(optarg); break;
        case 'r': www_root = optarg; break;
        case 'b': btn_path = optarg; break;
        case 'i': poll_ms = atoi(optarg); break;
        default:
            fprintf(stderr, "usage: %s [-p PORT] [-r ROOT] [-b BTN] [-i MS]\n",
                    argv[0]);
            return 2;
        }
    }
    if (poll_ms < 2 || poll_ms > 1000) poll_ms = 10;

    signal(SIGPIPE, SIG_IGN);
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    for (int i = 0; i < MAX_CLIENTS; i++) clients[i].fd = -1;

    listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd < 0) die("socket");
    int one = 1;
    setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = htonl(INADDR_ANY);
    sa.sin_port = htons((unsigned short)port);
    if (bind(listen_fd, (struct sockaddr *)&sa, sizeof(sa)) < 0) die("bind");
    if (listen(listen_fd, 16) < 0) die("listen");
    set_nonblock(listen_fd);

    btn_event_fd = open("/dev/chiplab_btn_events", O_RDONLY);
    if (btn_event_fd >= 0) {
        btn_use_events = 1;
        set_nonblock(btn_event_fd);
    } else {
        btn_fd = open("/dev/chiplab_confreg", O_RDONLY);
        if (btn_fd >= 0) {
            btn_is_chardev = 1;
            set_nonblock(btn_fd);
        } else {
            btn_fd = open(btn_path, O_RDONLY);
            if (btn_fd >= 0) set_nonblock(btn_fd);
        }
    }

    struct timeval next_btn;
    gettimeofday(&next_btn, NULL);

    while (running) {
        struct timeval now;
        gettimeofday(&now, NULL);
        long diff_ms;
        if (btn_use_events) {
            diff_ms = 1000;
        } else if (active_sse > 0) {
            diff_ms = (next_btn.tv_sec - now.tv_sec) * 1000L +
                      (next_btn.tv_usec - now.tv_usec) / 1000L;
        } else {
            diff_ms = 1000;
        }
        if (!btn_use_events && diff_ms <= 0) {
            poll_button();
            next_btn = now;
            next_btn.tv_usec += poll_ms * 1000;
            if (next_btn.tv_usec >= 1000000) {
                next_btn.tv_sec += next_btn.tv_usec / 1000000;
                next_btn.tv_usec %= 1000000;
            }
            continue;
        }

        fd_set rfds, wfds;
        FD_ZERO(&rfds);
        FD_ZERO(&wfds);
        FD_SET(listen_fd, &rfds);
        int maxfd = listen_fd;
        if (btn_event_fd >= 0) {
            FD_SET(btn_event_fd, &rfds);
            if (btn_event_fd > maxfd) maxfd = btn_event_fd;
        }
        for (int i = 0; i < MAX_CLIENTS; i++) {
            struct client *c = &clients[i];
            if (c->fd < 0) continue;
            FD_SET(c->fd, &rfds);
            if (c->response || c->sse) FD_SET(c->fd, &wfds);
            if (c->fd > maxfd) maxfd = c->fd;
        }
        struct timeval tv;
        tv.tv_sec = diff_ms / 1000;
        tv.tv_usec = (diff_ms % 1000) * 1000;

        int rc = select(maxfd + 1, &rfds, &wfds, NULL, &tv);
        if (rc < 0) {
            if (errno == EINTR) continue;
            die("select");
        }
        if (rc == 0) continue;
        if (btn_event_fd >= 0 && FD_ISSET(btn_event_fd, &rfds))
            read_button_events();
        if (FD_ISSET(listen_fd, &rfds)) accept_clients();
        parse_requests();
        write_clients();
    }

    for (int i = 0; i < MAX_CLIENTS; i++)
        if (clients[i].fd >= 0) close_client(i);
    if (btn_event_fd >= 0) close(btn_event_fd);
    if (btn_fd >= 0) close(btn_fd);
    close(listen_fd);
    return 0;
}
