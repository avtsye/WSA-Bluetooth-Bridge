#include "compat_audio_hal.h"
#include <arpa/inet.h>
#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define SAMPLE_RATE 48000u
#define OUT_CHANNELS AUDIO_CHANNEL_OUT_STEREO
#define IN_CHANNELS AUDIO_CHANNEL_IN_MONO
#define BUFFER_BYTES 3840u
#define WSAB_VERSION 1
#define STREAM_PLAYBACK 1
#define STREAM_CAPTURE 2

struct wsa_out {
    struct audio_stream_out stream;
    audio_devices_t device;
    uint64_t frames;
};

struct wsa_in {
    struct audio_stream_in stream;
    audio_devices_t device;
    int64_t frames;
};

struct bridge_state {
    pthread_mutex_t lock;
    int fd;
    uint32_t tx_seq;
    int refs;
    uint8_t rx[262144];
    size_t rx_off;
    size_t rx_len;
};

static struct bridge_state g_bridge = {
    .lock = PTHREAD_MUTEX_INITIALIZER,
    .fd = -1,
};

static int connect_abstract(const char* name) {
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return -1;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    addr.sun_path[0] = 0;
    size_t n = strlen(name);
    if (n + 1 >= sizeof(addr.sun_path)) { close(fd); errno = ENAMETOOLONG; return -1; }
    memcpy(addr.sun_path + 1, name, n);
    socklen_t len = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + 1 + n);
    if (connect(fd, (struct sockaddr*)&addr, len) != 0) { close(fd); return -1; }
    return fd;
}

static int write_all(int fd, const void* data, size_t len) {
    const uint8_t* p = (const uint8_t*)data;
    while (len) {
        ssize_t n = write(fd, p, len);
        if (n < 0) { if (errno == EINTR) continue; return -1; }
        if (n == 0) return -1;
        p += n; len -= (size_t)n;
    }
    return 0;
}

static int read_all(int fd, void* data, size_t len) {
    uint8_t* p = (uint8_t*)data;
    while (len) {
        ssize_t n = read(fd, p, len);
        if (n < 0) { if (errno == EINTR) continue; return -1; }
        if (n == 0) return -1;
        p += n; len -= (size_t)n;
    }
    return 0;
}

static void put_u32le(uint8_t* p, uint32_t v) {
    p[0]=(uint8_t)v; p[1]=(uint8_t)(v>>8); p[2]=(uint8_t)(v>>16); p[3]=(uint8_t)(v>>24);
}
static uint32_t get_u32le(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1]<<8) | ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24);
}

static int bridge_ensure_locked(void) {
    if (g_bridge.fd >= 0) return 0;
    g_bridge.fd = connect_abstract("wsa_bt_audio");
    g_bridge.rx_off = g_bridge.rx_len = 0;
    g_bridge.tx_seq = 0;
    return g_bridge.fd >= 0 ? 0 : -1;
}

static void bridge_reset_locked(void) {
    if (g_bridge.fd >= 0) close(g_bridge.fd);
    g_bridge.fd = -1;
    g_bridge.rx_off = g_bridge.rx_len = 0;
}

static int bridge_send_frame(const void* data, size_t len) {
    pthread_mutex_lock(&g_bridge.lock);
    if (bridge_ensure_locked() != 0) { pthread_mutex_unlock(&g_bridge.lock); return -1; }
    uint8_t h[16] = {'W','S','A','B',WSAB_VERSION,STREAM_PLAYBACK,0,0,0,0,0,0,0,0,0,0};
    put_u32le(h+8, (uint32_t)len);
    put_u32le(h+12, g_bridge.tx_seq++);
    int ok = write_all(g_bridge.fd, h, sizeof(h)) == 0 && write_all(g_bridge.fd, data, len) == 0;
    if (!ok) bridge_reset_locked();
    pthread_mutex_unlock(&g_bridge.lock);
    return ok ? 0 : -1;
}

static ssize_t bridge_read_capture(void* out, size_t bytes) {
    pthread_mutex_lock(&g_bridge.lock);
    if (bridge_ensure_locked() != 0) { pthread_mutex_unlock(&g_bridge.lock); return -1; }

    size_t done = 0;
    while (done < bytes) {
        if (g_bridge.rx_off < g_bridge.rx_len) {
            size_t avail = g_bridge.rx_len - g_bridge.rx_off;
            size_t take = (bytes - done < avail) ? (bytes - done) : avail;
            memcpy((uint8_t*)out + done, g_bridge.rx + g_bridge.rx_off, take);
            g_bridge.rx_off += take; done += take;
            continue;
        }

        uint8_t h[16];
        if (read_all(g_bridge.fd, h, sizeof(h)) != 0 ||
            memcmp(h, "WSAB", 4) != 0 || h[4] != WSAB_VERSION) {
            bridge_reset_locked(); pthread_mutex_unlock(&g_bridge.lock); return -1;
        }
        uint32_t len = get_u32le(h+8);
        if (len > sizeof(g_bridge.rx)) {
            bridge_reset_locked(); pthread_mutex_unlock(&g_bridge.lock); return -1;
        }
        if (read_all(g_bridge.fd, g_bridge.rx, len) != 0) {
            bridge_reset_locked(); pthread_mutex_unlock(&g_bridge.lock); return -1;
        }
        if (h[5] != STREAM_CAPTURE) continue;
        g_bridge.rx_off = 0;
        g_bridge.rx_len = len;
    }
    pthread_mutex_unlock(&g_bridge.lock);
    return (ssize_t)done;
}

static void control_command(const char* json_line) {
    int fd = connect_abstract("wsa_bt_bridge");
    if (fd < 0) return;
    char buf[1024];
    (void)read(fd, buf, sizeof(buf)); /* hello */
    write_all(fd, json_line, strlen(json_line));
    write_all(fd, "\n", 1);
    (void)read(fd, buf, sizeof(buf));
    close(fd);
}

static uint32_t s_rate(const struct audio_stream* s){ (void)s; return SAMPLE_RATE; }
static int s_set_rate(struct audio_stream* s,uint32_t r){(void)s; return r==SAMPLE_RATE?0:-EINVAL;}
static size_t s_buf(const struct audio_stream* s){(void)s; return BUFFER_BYTES;}
static audio_channel_mask_t out_ch(const struct audio_stream* s){(void)s; return OUT_CHANNELS;}
static audio_channel_mask_t in_ch(const struct audio_stream* s){(void)s; return IN_CHANNELS;}
static audio_format_t s_fmt(const struct audio_stream* s){(void)s; return AUDIO_FORMAT_PCM_16_BIT;}
static int s_set_fmt(struct audio_stream* s,audio_format_t f){(void)s; return f==AUDIO_FORMAT_PCM_16_BIT?0:-EINVAL;}
static int s_ok(struct audio_stream* s){(void)s; return 0;}
static int s_dump(const struct audio_stream* s,int fd){(void)s;(void)fd;return 0;}
static audio_devices_t s_get_dev(const struct audio_stream* s){(void)s;return 0;}
static int s_set_dev(struct audio_stream* s,audio_devices_t d){(void)s;(void)d;return 0;}
static int s_params(struct audio_stream* s,const char* p){(void)s;(void)p;return 0;}
static char* s_get_params(const struct audio_stream* s,const char* k){(void)s;(void)k;return strdup("");}
static int s_effect(const struct audio_stream* s,effect_handle_t e){(void)s;(void)e;return 0;}

static uint32_t o_latency(const struct audio_stream_out* s){(void)s;return 80;}
static int o_volume(struct audio_stream_out* s,float l,float r){(void)s;(void)l;(void)r;return 0;}
static ssize_t o_write(struct audio_stream_out* s,const void* b,size_t n){
    struct wsa_out* o=(struct wsa_out*)s;
    if (bridge_send_frame(b,n)!=0) {
        usleep((useconds_t)((1000000ULL*n)/(SAMPLE_RATE*2*2)));
        return (ssize_t)n;
    }
    o->frames += n/4;
    return (ssize_t)n;
}
static int o_pos(const struct audio_stream_out* s,uint32_t* f){*f=(uint32_t)((const struct wsa_out*)s)->frames;return 0;}
static int o_ts(const struct audio_stream_out* s,int64_t* t){(void)s;(void)t;return -ENOSYS;}
static int o_cb(struct audio_stream_out* s,stream_callback_t c,void* x){(void)s;(void)c;(void)x;return -ENOSYS;}
static int o_no(struct audio_stream_out* s){(void)s;return -ENOSYS;}
static int o_drain(struct audio_stream_out* s,int t){(void)s;(void)t;return 0;}
static int o_pp(const struct audio_stream_out* s,uint64_t* f,struct timespec* ts){
    *f=((const struct wsa_out*)s)->frames; clock_gettime(CLOCK_MONOTONIC,ts); return 0;
}

static int i_gain(struct audio_stream_in* s,float g){(void)s;(void)g;return 0;}
static ssize_t i_read(struct audio_stream_in* s,void* b,size_t n){
    struct wsa_in* in=(struct wsa_in*)s;
    ssize_t r=bridge_read_capture(b,n);
    if(r<0){ memset(b,0,n); usleep((useconds_t)((1000000ULL*n)/(SAMPLE_RATE*2))); r=(ssize_t)n; }
    in->frames += r/2;
    return r;
}
static uint32_t i_lost(struct audio_stream_in* s){(void)s;return 0;}
static int i_pos(const struct audio_stream_in* s,int64_t* f,int64_t* t){
    *f=((const struct wsa_in*)s)->frames; struct timespec ts; clock_gettime(CLOCK_MONOTONIC,&ts);
    *t=(int64_t)ts.tv_sec*1000000000LL+ts.tv_nsec; return 0;
}

static void init_common(struct audio_stream* s, bool input){
    memset(s,0,sizeof(*s)); s->get_sample_rate=s_rate; s->set_sample_rate=s_set_rate;
    s->get_buffer_size=s_buf; s->get_channels=input?in_ch:out_ch; s->get_format=s_fmt;
    s->set_format=s_set_fmt; s->standby=s_ok; s->dump=s_dump; s->get_device=s_get_dev;
    s->set_device=s_set_dev; s->set_parameters=s_params; s->get_parameters=s_get_params;
    s->add_audio_effect=s_effect; s->remove_audio_effect=s_effect;
}

static int dev_close(struct hw_device_t* d){ free(d); return 0; }
static int dev_init(const struct audio_hw_device* d){(void)d;return 0;}
static int dev_f(struct audio_hw_device* d,float v){(void)d;(void)v;return -ENOSYS;}
static int dev_get_f(struct audio_hw_device* d,float* v){(void)d;if(v)*v=1.0f;return -ENOSYS;}
static int dev_mode(struct audio_hw_device* d,audio_mode_t m){(void)d;(void)m;return 0;}
static int dev_mic(struct audio_hw_device* d,bool m){(void)d;(void)m;return 0;}
static int dev_get_mic(const struct audio_hw_device* d,bool* m){(void)d;if(m)*m=false;return 0;}
static int dev_params(struct audio_hw_device* d,const char* p){(void)d;(void)p;return 0;}
static char* dev_get_params(const struct audio_hw_device* d,const char* k){(void)d;(void)k;return strdup("");}
static size_t dev_in_buf(const struct audio_hw_device* d,const struct audio_config* c){(void)d;(void)c;return BUFFER_BYTES;}

static int open_out(struct audio_hw_device* d,audio_io_handle_t h,audio_devices_t dev,
                    audio_output_flags_t fl,struct audio_config* cfg,struct audio_stream_out** out,const char* addr){
    (void)d;(void)h;(void)fl;(void)addr;
    struct wsa_out* o=(struct wsa_out*)calloc(1,sizeof(*o)); if(!o)return -ENOMEM;
    init_common(&o->stream.common,false); o->device=dev;
    o->stream.get_latency=o_latency; o->stream.set_volume=o_volume; o->stream.write=o_write;
    o->stream.get_render_position=o_pos; o->stream.get_next_write_timestamp=o_ts;
    o->stream.set_callback=o_cb; o->stream.pause=o_no; o->stream.resume=o_no;
    o->stream.drain=o_drain; o->stream.flush=o_no; o->stream.get_presentation_position=o_pp;
    if(cfg){cfg->sample_rate=SAMPLE_RATE;cfg->channel_mask=OUT_CHANNELS;cfg->format=AUDIO_FORMAT_PCM_16_BIT;}
    *out=&o->stream;
    pthread_mutex_lock(&g_bridge.lock); g_bridge.refs++; pthread_mutex_unlock(&g_bridge.lock);
    control_command("{\"type\":\"audio.playback.start\",\"sampleRate\":48000,\"channels\":2}");
    return 0;
}
static void close_out(struct audio_hw_device* d,struct audio_stream_out* s){
    (void)d; free(s); control_command("{\"type\":\"audio.playback.stop\"}");
    pthread_mutex_lock(&g_bridge.lock); if(--g_bridge.refs<=0)bridge_reset_locked(); pthread_mutex_unlock(&g_bridge.lock);
}
static int open_in(struct audio_hw_device* d,audio_io_handle_t h,audio_devices_t dev,
                   struct audio_config* cfg,struct audio_stream_in** in,audio_input_flags_t fl,const char* addr,audio_source_t src){
    (void)d;(void)h;(void)fl;(void)addr;(void)src;
    struct wsa_in* x=(struct wsa_in*)calloc(1,sizeof(*x)); if(!x)return -ENOMEM;
    init_common(&x->stream.common,true); x->device=dev;
    x->stream.set_gain=i_gain; x->stream.read=i_read; x->stream.get_input_frames_lost=i_lost; x->stream.get_capture_position=i_pos;
    if(cfg){cfg->sample_rate=SAMPLE_RATE;cfg->channel_mask=IN_CHANNELS;cfg->format=AUDIO_FORMAT_PCM_16_BIT;}
    *in=&x->stream;
    pthread_mutex_lock(&g_bridge.lock); g_bridge.refs++; pthread_mutex_unlock(&g_bridge.lock);
    control_command("{\"type\":\"audio.capture.start\"}");
    return 0;
}
static void close_in(struct audio_hw_device* d,struct audio_stream_in* s){
    (void)d; free(s); control_command("{\"type\":\"audio.capture.stop\"}");
    pthread_mutex_lock(&g_bridge.lock); if(--g_bridge.refs<=0)bridge_reset_locked(); pthread_mutex_unlock(&g_bridge.lock);
}

static int hal_open(const struct hw_module_t* module,const char* name,struct hw_device_t** out){
    if(!name || strcmp(name,AUDIO_HARDWARE_INTERFACE)!=0)return -EINVAL;
    struct audio_hw_device* d=(struct audio_hw_device*)calloc(1,sizeof(*d)); if(!d)return -ENOMEM;
    d->common.tag=HARDWARE_DEVICE_TAG; d->common.version=AUDIO_DEVICE_API_VERSION_3_0;
    d->common.module=(struct hw_module_t*)module; d->common.close=dev_close;
    d->init_check=dev_init; d->set_voice_volume=dev_f; d->set_master_volume=dev_f; d->get_master_volume=dev_get_f;
    d->set_mode=dev_mode; d->set_mic_mute=dev_mic; d->get_mic_mute=dev_get_mic;
    d->set_parameters=dev_params; d->get_parameters=dev_get_params; d->get_input_buffer_size=dev_in_buf;
    d->open_output_stream=open_out; d->close_output_stream=close_out; d->open_input_stream=open_in; d->close_input_stream=close_in;
    *out=&d->common; return 0;
}

static struct hw_module_methods_t methods={.open=hal_open};

__attribute__((visibility("default")))
struct hw_module_t HMI={
    .tag=HARDWARE_MODULE_TAG,
    .module_api_version=AUDIO_MODULE_API_VERSION_0_1,
    .hal_api_version=HARDWARE_HAL_API_VERSION,
    .id=AUDIO_HARDWARE_MODULE_ID,
    .name="WSA Bridge Audio HAL",
    .author="avtsye",
    .methods=&methods,
};
