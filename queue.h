#ifndef _QUEUE_H_
#define _QUEUE_H_

typedef struct queue_t {
    struct queue_t *prev;
    union {
        struct queue_t *parent;
        size_t size;
    };
    struct queue_t *next;
} queue_t;

/* rr core struct */
typedef struct ngx_http_upstream_rr_peer_s  ngx_http_upstream_rr_peer_t;
typedef struct {
    ngx_uint_t                     number;
    ngx_flag_t                     single;
    ngx_http_upstream_rr_peer_t   *peer;
} ngx_http_upstream_rr_peers_t;
typedef struct {
    ngx_http_upstream_rr_peers_t  *peers;
    ngx_http_upstream_rr_peer_t   *peer;
    ngx_uint_t                    tried;
} ngx_http_upstream_rr_peer_data_t;
typedef struct ngx_http_upstream_rr_peer_s {
    ngx_sockaddr_t                 sockaddr;
    socklen_t                      socklen;
    ngx_str_t                      name;
    ngx_uint_t                     fails;
    ngx_msec_t                     accessed;
    ngx_uint_t                     max_fails;
    ngx_msec_t                     fail_timeout;
    ngx_uint_t                     down;
    ngx_http_upstream_rr_peer_t   *next;
} ngx_http_upstream_rr_peer_s;

#define queue_parent(q) (q)->parent

#define queue_size(q) (q)->size

#define queue_init(q) \
    do { \
        (q)->prev = q; \
        (q)->size = 0; \
        (q)->next = q; \
    } while (0)

#define queue_empty(h) ((h) == (h)->prev)

#define queue_insert_head(h, x) \
    do { \
        (x)->next = (h)->next; \
        (x)->next->prev = x; \
        (x)->prev = h; \
        (h)->next = x; \
        (x)->parent = h; \
        (h)->size++; \
    } while (0)

#define queue_insert_after queue_insert_head

#define queue_insert_tail(h, x) \
    do { \
        (x)->prev = (h)->prev; \
        (x)->prev->next = x; \
        (x)->next = h; \
        (h)->prev = x; \
        (x)->parent = h; \
        (h)->size++; \
    } while (0)

#define queue_head(h) (h)->next

#define queue_last(h) (h)->prev

#define queue_sentinel(h) (h)

#define queue_next(q) (q)->next

#define queue_prev(q) (q)->prev

#define queue_remove(x) \
    do { \
        (x)->next->prev = (x)->prev; \
        (x)->prev->next = (x)->next; \
        (x)->prev = NULL; \
        (x)->next = NULL; \
        (x)->parent->size--; \
        (x)->parent = NULL; \
    } while (0)

#define queue_data(q, t, o) (t *)((char *)q - offsetof(t, o))

#define queue_each(h, q) for (queue_t *(q) = (h)->next, *_; (q) != (h) && (_ = (q)->next); (q) = _)

#endif // _QUEUE_H_
