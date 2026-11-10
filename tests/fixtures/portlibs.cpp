// Global initialization keeps the linkage probe alive under --gc-sections.
#include <png.h>
#include <zlib.h>

volatile unsigned long devkitpro_portlibs_probe = []() -> unsigned long {
    png_structp png = png_create_read_struct(PNG_LIBPNG_VER_STRING, nullptr, nullptr, nullptr);
    if (png) {
        png_destroy_read_struct(&png, nullptr, nullptr);
    }
    const unsigned char bytes[] = {1, 2, 3, 4};
    return png_access_version_number() + crc32(0, bytes, sizeof(bytes));
}();
