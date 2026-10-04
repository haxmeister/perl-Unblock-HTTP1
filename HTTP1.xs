#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "vendor/picohttpparser/picohttpparser.c"

#define UB_HTTP1_MAX_HEADERS 256
#define UB_BODY_NONE 0
#define UB_BODY_CONTENT_LENGTH 1
#define UB_BODY_CHUNKED 2

static int
ascii_equal_ci(const char *left, size_t left_len, const char *right, size_t right_len)
{
    size_t i;
    if (left_len != right_len)
        return 0;
    for (i = 0; i < left_len; ++i) {
        unsigned char a = (unsigned char)left[i];
        unsigned char b = (unsigned char)right[i];
        if (a >= 'A' && a <= 'Z') a = (unsigned char)(a + ('a' - 'A'));
        if (b >= 'A' && b <= 'Z') b = (unsigned char)(b + ('a' - 'A'));
        if (a != b) return 0;
    }
    return 1;
}

static int
is_ows(unsigned char c)
{
    return c == ' ' || c == '\t';
}

static int
is_tchar(unsigned char c)
{
    if ((c >= '0' && c <= '9') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= 'a' && c <= 'z'))
        return 1;
    switch (c) {
        case '!': case '#': case '$': case '%': case '&': case '\'':
        case '*': case '+': case '-': case '.': case '^': case '_':
        case 0x60: case '|': case '~':
            return 1;
        default:
            return 0;
    }
}

static int
valid_field_name(const char *name, size_t len)
{
    size_t i;
    if (len == 0) return 0;
    for (i = 0; i < len; ++i)
        if (!is_tchar((unsigned char)name[i])) return 0;
    return 1;
}

static int
valid_field_value(const char *value, size_t len)
{
    size_t i;
    for (i = 0; i < len; ++i) {
        unsigned char c = (unsigned char)value[i];
        if (c == '\t') continue;
        if (c < 0x20 || c == 0x7f) return 0;
    }
    return 1;
}

static int
valid_host_value(const char *value, size_t len)
{
    size_t i;
    size_t close_bracket = (size_t)-1;
    size_t colon_count = 0;
    if (len == 0) return 1;
    for (i = 0; i < len; ++i) {
        unsigned char c = (unsigned char)value[i];
        if (c <= 0x20 || c >= 0x7f) return 0;
        if (c == '/' || c == '?' || c == '#' || c == '@') return 0;
    }
    if (value[0] == '[') {
        for (i = 1; i < len; ++i) {
            if (value[i] == ']') { close_bracket = i; break; }
        }
        if (close_bracket == (size_t)-1 || close_bracket == 1) return 0;
        if (close_bracket + 1 == len) return 1;
        if (value[close_bracket + 1] != ':') return 0;
        if (close_bracket + 2 == len) return 1;
        for (i = close_bracket + 2; i < len; ++i)
            if (value[i] < '0' || value[i] > '9') return 0;
        return 1;
    }
    for (i = 0; i < len; ++i) {
        if (value[i] == ':') {
            size_t j;
            ++colon_count;
            if (colon_count > 1) return 0;
            for (j = i + 1; j < len; ++j)
                if (value[j] < '0' || value[j] > '9') return 0;
            break;
        }
    }
    return 1;
}

static int
ascii_equal_cs(const char *left, size_t left_len, const char *right, size_t right_len)
{
    return left_len == right_len && memEQ(left, right, right_len);
}

static int
valid_port_number(const char *value, size_t len)
{
    size_t i;
    unsigned int port = 0;
    if (len == 0) return 0;
    for (i = 0; i < len; ++i) {
        unsigned int digit;
        if (value[i] < '0' || value[i] > '9') return 0;
        digit = (unsigned int)(value[i] - '0');
        if (port > 6553 || (port == 6553 && digit > 5)) return 0;
        port = port * 10 + digit;
    }
    return port != 0;
}

static int
valid_connect_authority(const char *target, size_t len)
{
    size_t i;
    if (len < 3) return 0;

    if (target[0] == '[') {
        size_t close_bracket = (size_t)-1;
        for (i = 1; i < len; ++i) {
            if (target[i] == ']') {
                close_bracket = i;
                break;
            }
        }
        if (close_bracket == (size_t)-1 || close_bracket == 1) return 0;
        if (close_bracket + 2 >= len || target[close_bracket + 1] != ':')
            return 0;
        for (i = 1; i < close_bracket; ++i) {
            unsigned char ch = (unsigned char)target[i];
            if (ch <= 0x20 || ch == 0x7f ||
                ch == '/' || ch == '?' || ch == '#' || ch == '@')
                return 0;
        }
        return valid_port_number(
            target + close_bracket + 2,
            len - close_bracket - 2
        );
    }

    {
        size_t colon = (size_t)-1;
        for (i = 0; i < len; ++i) {
            unsigned char ch = (unsigned char)target[i];
            if (ch <= 0x20 || ch == 0x7f ||
                ch == '/' || ch == '?' || ch == '#' || ch == '@')
                return 0;
            if (target[i] == ':') {
                if (colon != (size_t)-1) return 0;
                colon = i;
            }
        }
        if (colon == (size_t)-1 || colon == 0 || colon + 1 == len) return 0;
        return valid_port_number(target + colon + 1, len - colon - 1);
    }
}

static int
connect_host_matches_target(const char *host, size_t host_len,
                            const char *target, size_t target_len)
{
    size_t target_host_len = 0;
    size_t compare_host_len = host_len;
    size_t i;

    if (ascii_equal_ci(host, host_len, target, target_len))
        return 1;

    if (host_len && host[host_len - 1] == ':')
        --compare_host_len;

    if (target_len == 0)
        return 0;

    if (target[0] == '[') {
        for (i = 1; i < target_len; ++i) {
            if (target[i] == ']') {
                target_host_len = i + 1;
                break;
            }
        }
    } else {
        for (i = 0; i < target_len; ++i) {
            if (target[i] == ':') {
                target_host_len = i;
                break;
            }
        }
    }

    return target_host_len != 0
        && ascii_equal_ci(host, compare_host_len, target, target_host_len);
}

static int
valid_request_target(const char *method, size_t method_len,
                     const char *target, size_t target_len)
{
    size_t i;
    if (target_len == 0) return 0;

    for (i = 0; i < target_len; ++i)
        if (target[i] == '#') return 0;

    if (target_len == 1 && target[0] == '*')
        return ascii_equal_cs(method, method_len, "OPTIONS", 7);

    if (ascii_equal_cs(method, method_len, "CONNECT", 7))
        return valid_connect_authority(target, target_len);

    if (target[0] == '/') return 1;

    if (!((target[0] >= 'A' && target[0] <= 'Z') ||
          (target[0] >= 'a' && target[0] <= 'z')))
        return 0;

    for (i = 1; i < target_len; ++i) {
        unsigned char ch = (unsigned char)target[i];
        if (ch == ':') {
            if (ascii_equal_ci(target, i, "http", 4) ||
                ascii_equal_ci(target, i, "https", 5)) {
                size_t pos = i + 1;
                size_t authority_start;

                if (pos + 1 >= target_len ||
                    target[pos] != '/' || target[pos + 1] != '/')
                    return 0;

                pos += 2;
                authority_start = pos;
                while (pos < target_len &&
                       target[pos] != '/' && target[pos] != '?') {
                    if (target[pos] == '@')
                        return 0;
                    ++pos;
                }
                if (pos == authority_start || target[authority_start] == ':')
                    return 0;
            }
            return 1;
        }
        if (!((ch >= 'A' && ch <= 'Z') ||
              (ch >= 'a' && ch <= 'z') ||
              (ch >= '0' && ch <= '9') ||
              ch == '+' || ch == '-' || ch == '.'))
            return 0;
    }
    return 0;
}

static int
parse_content_length(const char *value, size_t len, UV *out, int *seen)
{
    size_t pos = 0;
    int members = 0;
    const UV uv_max = ~(UV)0;
    while (1) {
        UV parsed = 0;
        int digits = 0;
        while (pos < len && is_ows((unsigned char)value[pos])) ++pos;
        if (pos == len) return 0;
        while (pos < len && value[pos] >= '0' && value[pos] <= '9') {
            UV digit = (UV)(value[pos] - '0');
            if (parsed > uv_max / 10 ||
                (parsed == uv_max / 10 && digit > uv_max % 10))
                return 0;
            parsed = parsed * 10 + digit;
            ++pos;
            ++digits;
        }
        if (!digits) return 0;
        while (pos < len && is_ows((unsigned char)value[pos])) ++pos;
        if (*seen) {
            if (*out != parsed) return 0;
        } else {
            *out = parsed;
            *seen = 1;
        }
        ++members;
        if (pos == len) break;
        if (value[pos] != ',') return 0;
        ++pos;
    }
    return members != 0;
}

static void
parse_connection(const char *value, size_t len, int *close_seen, int *keep_seen)
{
    size_t pos = 0;
    while (pos < len) {
        size_t start, end;
        while (pos < len && is_ows((unsigned char)value[pos])) ++pos;
        start = pos;
        while (pos < len && value[pos] != ',') ++pos;
        end = pos;
        while (end > start && is_ows((unsigned char)value[end - 1])) --end;
        if (end > start) {
            if (ascii_equal_ci(value + start, end - start, "close", 5))
                *close_seen = 1;
            else if (ascii_equal_ci(value + start, end - start, "keep-alive", 10))
                *keep_seen = 1;
        }
        if (pos < len) ++pos;
    }
}

static int
parse_transfer_encoding(const char *value, size_t len,
                        int *count, int *chunked_count,
                        int *final_chunked, int *unsupported)
{
    size_t pos = 0;
    while (1) {
        size_t start, token_end, member_end, tail;
        int chunked;
        while (pos < len && is_ows((unsigned char)value[pos])) ++pos;
        if (pos == len) return 0;
        start = pos;
        while (pos < len && is_tchar((unsigned char)value[pos])) ++pos;
        token_end = pos;
        if (token_end == start) return 0;
        while (pos < len && value[pos] != ',') ++pos;
        member_end = pos;
        while (member_end > token_end && is_ows((unsigned char)value[member_end - 1])) --member_end;
        chunked = ascii_equal_ci(value + start, token_end - start, "chunked", 7);
        if (chunked) {
            tail = token_end;
            while (tail < member_end && is_ows((unsigned char)value[tail])) ++tail;
            if (tail != member_end) return 0;
            ++*chunked_count;
        } else {
            *unsupported = 1;
        }
        ++*count;
        *final_chunked = chunked;
        if (pos == len) break;
        ++pos;
    }
    return *count != 0;
}

static int
parse_expect(const char *value, size_t len)
{
    size_t pos = 0;
    int members = 0;
    while (1) {
        size_t start, end;
        while (pos < len && is_ows((unsigned char)value[pos])) ++pos;
        start = pos;
        while (pos < len && value[pos] != ',') ++pos;
        end = pos;
        while (end > start && is_ows((unsigned char)value[end - 1])) --end;
        if (end == start || !ascii_equal_ci(value + start, end - start, "100-continue", 12))
            return -1;
        ++members;
        if (pos == len) break;
        ++pos;
    }
    return members ? 1 : -1;
}

static SV *
new_error_result(pTHX_ int status, const char *message)
{
    HV *hv = newHV();
    hv_store(hv, "ok", 2, newSViv(0), 0);
    if (status) hv_store(hv, "status", 6, newSViv(status), 0);
    hv_store(hv, "error", 5, newSVpv(message, 0), 0);
    return newRV_noinc((SV *)hv);
}

static AV *
headers_to_av(pTHX_ const struct phr_header *headers, size_t count)
{
    AV *out = newAV();
    size_t i;
    for (i = 0; i < count; ++i) {
        const char *value = headers[i].value;
        size_t value_len = headers[i].value_len;
        AV *pair;
        while (value_len && is_ows((unsigned char)*value)) { ++value; --value_len; }
        while (value_len && is_ows((unsigned char)value[value_len - 1])) --value_len;
        pair = newAV();
        av_push(pair, newSVpvn(headers[i].name, (STRLEN)headers[i].name_len));
        av_push(pair, newSVpvn(value, (STRLEN)value_len));
        av_push(out, newRV_noinc((SV *)pair));
    }
    return out;
}

static int
strict_headers(const struct phr_header *headers, size_t count)
{
    size_t i;
    for (i = 0; i < count; ++i) {
        if (headers[i].name == NULL ||
            !valid_field_name(headers[i].name, headers[i].name_len) ||
            !valid_field_value(headers[i].value, headers[i].value_len))
            return 0;
    }
    return 1;
}

MODULE = Unblock::HTTP1    PACKAGE = Unblock::HTTP1::_Native
PROTOTYPES: DISABLE

const char *
pico_version(CLASS)
    const char *CLASS
  CODE:
    (void)CLASS;
    RETVAL = PICOHTTPPARSER_VERSION;
  OUTPUT:
    RETVAL

SV *
parse_request_head(CLASS, buffer, last_len = 0, max_headers = 100)
    const char *CLASS
    SV *buffer
    UV last_len
    UV max_headers
  PREINIT:
    STRLEN buffer_len;
    const char *buf;
    const char *method;
    size_t method_len;
    const char *target;
    size_t target_len;
    int minor;
    struct phr_header headers[UB_HTTP1_MAX_HEADERS];
    size_t count;
    int consumed;
    size_t i;
    int host_count = 0;
    int has_cl = 0;
    UV content_length = 0;
    int te_present = 0;
    int te_count = 0;
    int chunked_count = 0;
    int final_chunked = 0;
    int unsupported = 0;
    int close_seen = 0;
    int keep_seen = 0;
    int expect_mode = 0;
    int body_mode = UB_BODY_NONE;
    int is_connect = 0;
    const char *host_value = NULL;
    size_t host_value_len = 0;
    HV *hv;
    AV *list;
  CODE:
    (void)CLASS;
    buf = SvPVbyte(buffer, buffer_len);
    if (last_len > (UV)buffer_len)
        croak("last_len exceeds buffer length");
    if (max_headers == 0 || max_headers > UB_HTTP1_MAX_HEADERS)
        croak("max_headers must be between 1 and %d", UB_HTTP1_MAX_HEADERS);
    count = (size_t)max_headers;
    consumed = phr_parse_request(buf, (size_t)buffer_len,
        &method, &method_len, &target, &target_len, &minor,
        headers, &count, (size_t)last_len);
    if (consumed == -2) XSRETURN_UNDEF;
    if (consumed == -1) {
        if (count == (size_t)max_headers)
            RETVAL = new_error_result(aTHX_ 431, "too many HTTP/1 request header fields");
        else
            RETVAL = new_error_result(aTHX_ 400, "malformed HTTP/1 request");
    } else if (minor != 0 && minor != 1) {
        RETVAL = new_error_result(aTHX_ 505, "unsupported HTTP/1 version");
    } else if (!strict_headers(headers, count)) {
        RETVAL = new_error_result(aTHX_ 400, "invalid or folded HTTP/1 header field");
    } else {
        const char *error = NULL;
        int error_status = 0;
        is_connect = ascii_equal_cs(method, method_len, "CONNECT", 7);
        if (!valid_request_target(method, method_len, target, target_len)) {
            error = "invalid HTTP/1 request target";
            error_status = 400;
        }
        if (!error && is_connect && minor != 1) {
            error = "CONNECT requires HTTP/1.1";
            error_status = 400;
        }
        for (i = 0; i < count && !error; ++i) {
            const char *name = headers[i].name;
            size_t name_len = headers[i].name_len;
            const char *value = headers[i].value;
            size_t value_len = headers[i].value_len;
            if (ascii_equal_ci(name, name_len, "Host", 4)) {
                ++host_count;
                if (host_count == 1) {
                    host_value = value;
                    host_value_len = value_len;
                }
                if (!valid_host_value(value, value_len)) {
                    error = "invalid Host field"; error_status = 400;
                }
            } else if (ascii_equal_ci(name, name_len, "Content-Length", 14)) {
                if (!parse_content_length(value, value_len, &content_length, &has_cl)) {
                    error = "invalid or conflicting Content-Length"; error_status = 400;
                }
            } else if (ascii_equal_ci(name, name_len, "Transfer-Encoding", 17)) {
                te_present = 1;
                if (!parse_transfer_encoding(value, value_len, &te_count,
                        &chunked_count, &final_chunked, &unsupported)) {
                    error = "invalid Transfer-Encoding"; error_status = 400;
                }
            } else if (ascii_equal_ci(name, name_len, "Connection", 10)) {
                parse_connection(value, value_len, &close_seen, &keep_seen);
            } else if (ascii_equal_ci(name, name_len, "Expect", 6)) {
                int e = parse_expect(value, value_len);
                if (minor != 1 || e < 0) expect_mode = -1;
                else if (expect_mode >= 0) expect_mode = 1;
            }
        }
        if (!error && host_count > 1) {
            error = "multiple Host fields"; error_status = 400;
        }
        if (!error && minor == 1 && host_count != 1) {
            error = "HTTP/1.1 request requires exactly one Host field"; error_status = 400;
        }
        if (!error && te_present && has_cl) {
            error = "Transfer-Encoding and Content-Length cannot be combined"; error_status = 400;
        }
        if (!error && minor == 0 && te_present) {
            error = "HTTP/1.0 request must not contain Transfer-Encoding"; error_status = 400;
        }
        if (!error && is_connect && (te_present || has_cl)) {
            error = "CONNECT request must not contain content framing"; error_status = 400;
        }
        if (!error && is_connect && host_count == 1 &&
            !connect_host_matches_target(
                host_value, host_value_len, target, target_len
            )) {
            error = "CONNECT Host must identify request target"; error_status = 400;
        }
        if (!error && te_present) {
            if (chunked_count != 1 || !final_chunked) {
                error = "chunked must be the final and only chunked transfer coding"; error_status = 400;
            } else if (unsupported) {
                error = "unsupported transfer coding"; error_status = 501;
            } else {
                body_mode = UB_BODY_CHUNKED;
            }
        } else if (!error && has_cl) {
            body_mode = UB_BODY_CONTENT_LENGTH;
        }
        if (error) {
            RETVAL = new_error_result(aTHX_ error_status, error);
        } else {
            hv = newHV();
            hv_store(hv, "ok", 2, newSViv(1), 0);
            hv_store(hv, "consumed", 8, newSViv(consumed), 0);
            hv_store(hv, "version", 7, newSVpvf("1.%d", minor), 0);
            hv_store(hv, "method", 6, newSVpvn(method, (STRLEN)method_len), 0);
            hv_store(hv, "target", 6, newSVpvn(target, (STRLEN)target_len), 0);
            list = headers_to_av(aTHX_ headers, count);
            hv_store(hv, "headers", 7, newRV_noinc((SV *)list), 0);
            if (body_mode == UB_BODY_CHUNKED)
                hv_store(hv, "body_mode", 9, newSVpvs("chunked"), 0);
            else if (body_mode == UB_BODY_CONTENT_LENGTH)
                hv_store(hv, "body_mode", 9, newSVpvs("content-length"), 0);
            else
                hv_store(hv, "body_mode", 9, newSVpvs("none"), 0);
            if (has_cl)
                hv_store(hv, "content_length", 14, newSVuv(content_length), 0);
            hv_store(hv, "keep_alive", 10,
                newSViv(close_seen ? 0 : (minor == 1 ? 1 : (keep_seen ? 1 : 0))), 0);
            hv_store(hv, "expect_continue", 15, newSViv(expect_mode), 0);
            RETVAL = newRV_noinc((SV *)hv);
        }
    }
  OUTPUT:
    RETVAL

SV *
parse_response_head(CLASS, buffer, last_len = 0, max_headers = 100)
    const char *CLASS
    SV *buffer
    UV last_len
    UV max_headers
  PREINIT:
    STRLEN buffer_len;
    const char *buf;
    int minor;
    int status;
    const char *reason;
    size_t reason_len;
    struct phr_header headers[UB_HTTP1_MAX_HEADERS];
    size_t count;
    int consumed;
    HV *hv;
    AV *list;
  CODE:
    (void)CLASS;
    buf = SvPVbyte(buffer, buffer_len);
    if (last_len > (UV)buffer_len)
        croak("last_len exceeds buffer length");
    if (max_headers == 0 || max_headers > UB_HTTP1_MAX_HEADERS)
        croak("max_headers must be between 1 and %d", UB_HTTP1_MAX_HEADERS);
    count = (size_t)max_headers;
    consumed = phr_parse_response(buf, (size_t)buffer_len, &minor, &status,
        &reason, &reason_len, headers, &count, (size_t)last_len);
    if (consumed == -2) XSRETURN_UNDEF;
    if (consumed == -1 || (minor != 0 && minor != 1) || status < 100 || status > 599 ||
        buffer_len < 13 || !memEQ(buf, "HTTP/1.", 7) ||
        (buf[7] != '0' && buf[7] != '1') || buf[8] != ' ' ||
        buf[9] < '0' || buf[9] > '9' ||
        buf[10] < '0' || buf[10] > '9' ||
        buf[11] < '0' || buf[11] > '9' || buf[12] != ' ' ||
        reason != buf + 13 ||
        !valid_field_value(reason, reason_len) || !strict_headers(headers, count)) {
        RETVAL = new_error_result(aTHX_ 0, "malformed HTTP/1 response");
    } else {
        hv = newHV();
        hv_store(hv, "ok", 2, newSViv(1), 0);
        hv_store(hv, "consumed", 8, newSViv(consumed), 0);
        hv_store(hv, "version", 7, newSVpvf("1.%d", minor), 0);
        hv_store(hv, "status", 6, newSViv(status), 0);
        hv_store(hv, "reason", 6, newSVpvn(reason, (STRLEN)reason_len), 0);
        list = headers_to_av(aTHX_ headers, count);
        hv_store(hv, "headers", 7, newRV_noinc((SV *)list), 0);
        RETVAL = newRV_noinc((SV *)hv);
    }
  OUTPUT:
    RETVAL

SV *
parse_trailers(CLASS, buffer, last_len = 0, max_headers = 100)
    const char *CLASS
    SV *buffer
    UV last_len
    UV max_headers
  PREINIT:
    STRLEN buffer_len;
    const char *buf;
    struct phr_header headers[UB_HTTP1_MAX_HEADERS];
    size_t count;
    int consumed;
    HV *hv;
    AV *list;
  CODE:
    (void)CLASS;
    buf = SvPVbyte(buffer, buffer_len);
    if (last_len > (UV)buffer_len)
        croak("last_len exceeds buffer length");
    if (max_headers == 0 || max_headers > UB_HTTP1_MAX_HEADERS)
        croak("max_headers must be between 1 and %d", UB_HTTP1_MAX_HEADERS);
    count = (size_t)max_headers;
    consumed = phr_parse_headers(buf, (size_t)buffer_len, headers, &count, (size_t)last_len);
    if (consumed == -2) XSRETURN_UNDEF;
    if (consumed == -1 || !strict_headers(headers, count)) {
        RETVAL = new_error_result(aTHX_ 0, "malformed HTTP/1 trailer section");
    } else {
        hv = newHV();
        hv_store(hv, "ok", 2, newSViv(1), 0);
        hv_store(hv, "consumed", 8, newSViv(consumed), 0);
        list = headers_to_av(aTHX_ headers, count);
        hv_store(hv, "headers", 7, newRV_noinc((SV *)list), 0);
        RETVAL = newRV_noinc((SV *)hv);
    }
  OUTPUT:
    RETVAL

MODULE = Unblock::HTTP1    PACKAGE = Unblock::HTTP1::_Native::Chunked

SV *
new(CLASS)
    const char *CLASS
  PREINIT:
    struct phr_chunked_decoder *decoder;
    SV *inner;
    SV *obj;
  CODE:
    Newxz(decoder, 1, struct phr_chunked_decoder);
    decoder->consume_trailer = 0;
    inner = newSViv(PTR2IV(decoder));
    obj = newRV_noinc(inner);
    sv_bless(obj, gv_stashpv(CLASS, GV_ADD));
    RETVAL = obj;
  OUTPUT:
    RETVAL

void
feed(self, input, emit = 1)
    SV *self
    SV *input
    int emit
  PREINIT:
    struct phr_chunked_decoder *decoder;
    SV *inner;
    STRLEN input_len;
    const char *input_bytes;
    char *scratch;
    size_t decoded_len;
    ssize_t result;
    size_t leftover;
  PPCODE:
    if (!SvROK(self) || !sv_derived_from(self, "Unblock::HTTP1::_Native::Chunked"))
        croak("not an Unblock::HTTP1 chunked decoder object");
    inner = SvRV(self);
    decoder = INT2PTR(struct phr_chunked_decoder *, SvIV(inner));
    if (!decoder) croak("chunked decoder has already been released");
    input_bytes = SvPVbyte(input, input_len);
    Newx(scratch, input_len ? input_len : 1, char);
    if (input_len) Copy(input_bytes, scratch, input_len, char);
    decoded_len = (size_t)input_len;
    result = phr_decode_chunked(decoder, scratch, &decoded_len);
    if (result == -1) {
        Safefree(scratch);
        croak("malformed HTTP/1 chunked body");
    }
    leftover = result >= 0 ? (size_t)result : 0;
    XPUSHs(sv_2mortal(newSViv(result >= 0 ? 1 : 0)));
    if (emit)
        XPUSHs(sv_2mortal(newSVpvn(scratch, (STRLEN)decoded_len)));
    else
        XPUSHs(&PL_sv_undef);
    if (leftover)
        XPUSHs(sv_2mortal(newSVpvn(scratch + decoded_len, (STRLEN)leftover)));
    else
        XPUSHs(sv_2mortal(newSVpvn("", 0)));
    Safefree(scratch);

void
DESTROY(self)
    SV *self
  PREINIT:
    SV *inner;
    struct phr_chunked_decoder *decoder;
  CODE:
    if (!SvROK(self)) XSRETURN_EMPTY;
    inner = SvRV(self);
    decoder = INT2PTR(struct phr_chunked_decoder *, SvIV(inner));
    if (!decoder) XSRETURN_EMPTY;
    Safefree(decoder);
    sv_setiv(inner, 0);
