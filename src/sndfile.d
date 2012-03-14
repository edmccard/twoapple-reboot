module sndfile;

import derelict.util.loader;

/+
 + The following file types can be read and written.
 + A file type would consist of a major type (ie SF_FORMAT_WAV) bitwise
 + ORed with a minor type (ie SF_FORMAT_PCM). SF_FORMAT_TYPEMASK and
 + SF_FORMAT_SUBMASK can be used to separate the major and minor file
 + types.
 +/

enum
{   
    // Major formats.
    SF_FORMAT_WAV       = 0x010000,   /+ Microsoft WAV format
                                         (little endian default). +/
    SF_FORMAT_AIFF      = 0x020000,   // Apple/SGI AIFF format (big endian).
    SF_FORMAT_AU        = 0x030000,   // Sun/NeXT AU format (big endian).
    SF_FORMAT_RAW       = 0x040000,   // RAW PCM data.
    SF_FORMAT_PAF       = 0x050000,   // Ensoniq PARIS file format.
    SF_FORMAT_SVX       = 0x060000,   // Amiga IFF / SVX8 / SV16 format.
    SF_FORMAT_NIST      = 0x070000,   // Sphere NIST format.
    SF_FORMAT_VOC       = 0x080000,   // VOC files.
    SF_FORMAT_IRCAM     = 0x0A0000,   // Berkeley/IRCAM/CARL
    SF_FORMAT_W64       = 0x0B0000,   // Sonic Foundry's 64 bit RIFF/WAV
    SF_FORMAT_MAT4      = 0x0C0000,   // Matlab (tm) V4.2 / GNU Octave 2.0
    SF_FORMAT_MAT5      = 0x0D0000,   // Matlab (tm) V5.0 / GNU Octave 2.1
    SF_FORMAT_PVF       = 0x0E0000,   // Portable Voice Format
    SF_FORMAT_XI        = 0x0F0000,   // Fasttracker 2 Extended Instrument
    SF_FORMAT_HTK       = 0x100000,   // HMM Tool Kit format
    SF_FORMAT_SDS       = 0x110000,   // Midi Sample Dump Standard
    SF_FORMAT_AVR       = 0x120000,   // Audio Visual Research
    SF_FORMAT_WAVEX     = 0x130000,   // MS WAVE with WAVEFORMATEX
    SF_FORMAT_SD2       = 0x160000,   // Sound Designer 2
    SF_FORMAT_FLAC      = 0x170000,   // FLAC lossless file format
    SF_FORMAT_CAF       = 0x180000,   // Core Audio File format

    // Subtypes from here on.

    SF_FORMAT_PCM_S8    = 0x0001,     // Signed 8 bit data
    SF_FORMAT_PCM_16    = 0x0002,     // Signed 16 bit data
    SF_FORMAT_PCM_24    = 0x0003,     // Signed 24 bit data
    SF_FORMAT_PCM_32    = 0x0004,     // Signed 32 bit data

    SF_FORMAT_PCM_U8    = 0x0005,     /+ Unsigned 8 bit data
                                         (WAV and RAW only) +/

    SF_FORMAT_FLOAT     = 0x0006,     // 32 bit float data
    SF_FORMAT_DOUBLE    = 0x0007,     // 64 bit float data

    SF_FORMAT_ULAW      = 0x0010,     // U-Law encoded.
    SF_FORMAT_ALAW      = 0x0011,     // A-Law encoded.
    SF_FORMAT_IMA_ADPCM = 0x0012,     // IMA ADPCM.
    SF_FORMAT_MS_ADPCM  = 0x0013,     // Microsoft ADPCM.

    SF_FORMAT_GSM610    = 0x0020,     // GSM 6.10 encoding.
    SF_FORMAT_VOX_ADPCM = 0x0021,     // OKI / Dialogix ADPCM

    SF_FORMAT_G721_32   = 0x0030,     // 32kbs G721 ADPCM encoding.
    SF_FORMAT_G723_24   = 0x0031,     // 24kbs G723 ADPCM encoding.
    SF_FORMAT_G723_40   = 0x0032,     // 40kbs G723 ADPCM encoding.

    SF_FORMAT_DWVW_12   = 0x0040,     /+ 12 bit Delta Width Variable Word
                                         encoding. +/
    SF_FORMAT_DWVW_16   = 0x0041,     /+ 16 bit Delta Width Variable Word
                                         encoding. +/
    SF_FORMAT_DWVW_24   = 0x0042,     /+ 24 bit Delta Width Variable Word
                                         encoding. +/
    SF_FORMAT_DWVW_N    = 0x0043,     /+ N bit Delta Width Variable Word
                                         encoding. +/

    SF_FORMAT_DPCM_8    = 0x0050,     // 8 bit differential PCM (XI only)
    SF_FORMAT_DPCM_16   = 0x0051,     // 16 bit differential PCM (XI only)

    // Endian-ness options.

    SF_ENDIAN_FILE      = 0x00000000, // Default file endian-ness.
    SF_ENDIAN_LITTLE    = 0x10000000, // Force little endian-ness.
    SF_ENDIAN_BIG       = 0x20000000, // Force big endian-ness.
    SF_ENDIAN_CPU       = 0x30000000, // Force CPU endian-ness.

    SF_FORMAT_SUBMASK   = 0x0000FFFF,
    SF_FORMAT_TYPEMASK  = 0x0FFF0000,
    SF_FORMAT_ENDMASK   = 0x30000000
}

/+
 + The following are the valid command numbers for the sf_command()
 + interface.  The use of these commands is documented in the file
 + command.html in the doc directory of the source code distribution.
 +/

enum
{
    SFC_GET_LIB_VERSION             = 0x1000,
    SFC_GET_LOG_INFO                = 0x1001,

    SFC_GET_NORM_DOUBLE             = 0x1010,
    SFC_GET_NORM_FLOAT              = 0x1011,
    SFC_SET_NORM_DOUBLE             = 0x1012,
    SFC_SET_NORM_FLOAT              = 0x1013,
    SFC_SET_SCALE_FLOAT_INT_READ    = 0x1014,

    SFC_GET_SIMPLE_FORMAT_COUNT     = 0x1020,
    SFC_GET_SIMPLE_FORMAT           = 0x1021,

    SFC_GET_FORMAT_INFO             = 0x1028,

    SFC_GET_FORMAT_MAJOR_COUNT      = 0x1030,
    SFC_GET_FORMAT_MAJOR            = 0x1031,
    SFC_GET_FORMAT_SUBTYPE_COUNT    = 0x1032,
    SFC_GET_FORMAT_SUBTYPE          = 0x1033,

    SFC_CALC_SIGNAL_MAX             = 0x1040,
    SFC_CALC_NORM_SIGNAL_MAX        = 0x1041,
    SFC_CALC_MAX_ALL_CHANNELS       = 0x1042,
    SFC_CALC_NORM_MAX_ALL_CHANNELS  = 0x1043,
    SFC_GET_SIGNAL_MAX              = 0x1044,
    SFC_GET_MAX_ALL_CHANNELS        = 0x1045,

    SFC_SET_ADD_PEAK_CHUNK          = 0x1050,

    SFC_UPDATE_HEADER_NOW           = 0x1060,
    SFC_SET_UPDATE_HEADER_AUTO      = 0x1061,

    SFC_FILE_TRUNCATE               = 0x1080,

    SFC_SET_RAW_START_OFFSET        = 0x1090,

    SFC_SET_DITHER_ON_WRITE         = 0x10A0,
    SFC_SET_DITHER_ON_READ          = 0x10A1,

    SFC_GET_DITHER_INFO_COUNT       = 0x10A2,
    SFC_GET_DITHER_INFO             = 0x10A3,

    SFC_GET_EMBED_FILE_INFO         = 0x10B0,

    SFC_SET_CLIPPING                = 0x10C0,
    SFC_GET_CLIPPING                = 0x10C1,

    SFC_GET_INSTRUMENT              = 0x10D0,
    SFC_SET_INSTRUMENT              = 0x10D1,

    SFC_GET_LOOP_INFO               = 0x10E0,

    SFC_GET_BROADCAST_INFO          = 0x10F0,
    SFC_SET_BROADCAST_INFO          = 0x10F1,

    // Following commands for testing only.
    SFC_TEST_IEEE_FLOAT_REPLACE     = 0x6001,

    /+
     + SFC_SET_ADD_* values are deprecated and will disappear at some
     + time in the future. They are guaranteed to be here up to and
     + including version 1.0.8 to avoid breakage of existng software.
     + They currently do nothing and will continue to do nothing.
     +/
    SFC_SET_ADD_DITHER_ON_WRITE     = 0x1070,
    SFC_SET_ADD_DITHER_ON_READ      = 0x1071
}


/+
 + String types that can be set and read from files. Not all file types
 + support this and even the file types which support one, may not support
 + all string types.
 +/

enum
{   
    SF_STR_TITLE                    = 0x01,
    SF_STR_COPYRIGHT                = 0x02,
    SF_STR_SOFTWARE                 = 0x03,
    SF_STR_ARTIST                   = 0x04,
    SF_STR_COMMENT                  = 0x05,
    SF_STR_DATE                     = 0x06
}

/+
 + Use the following as the start and end index when doing metadata
 + transcoding.
 +/

alias SF_STR_TITLE SF_STR_FIRST;
alias SF_STR_DATE SF_STR_LAST;

enum
{
    // True and false
    SF_FALSE    = 0,
    SF_TRUE     = 1,

    // Modes for opening files.
    SFM_READ    = 0x10,
    SFM_WRITE   = 0x20,
    SFM_RDWR    = 0x30
}

/+
 + Public error values. These are guaranteed to remain unchanged for the
 + duration of the library major version number. There are also a large number
 + of private error numbers which are internal to the library which can change
 + at any time.
 +/

enum
{   
    SF_ERR_NO_ERROR             = 0,
    SF_ERR_UNRECOGNISED_FORMAT  = 1,
    SF_ERR_SYSTEM               = 2,
    SF_ERR_MALFORMED_FILE       = 3,
    SF_ERR_UNSUPPORTED_ENCODING = 4
}


// A SNDFILE* pointer can be passed around much like stdio.h's FILE* pointer.
struct SNDFILE_tag {}
alias SNDFILE_tag SNDFILE;

alias long sf_count_t;

enum : long
{
    SF_COUNT_MAX = 0x7FFFFFFFFFFFFFFFL
}

/+
 + A pointer to a SF_INFO structure is passed to sf_open_read() and filled in.
 + On write, the SF_INFO structure is filled in by the user and passed into
 + sf_open_write().
 +/

struct SF_INFO
{   
    sf_count_t  frames;        /+ Used to be called samples.
                                  Changed to avoid confusion. +/
    int         samplerate;
    int         channels;
    int         format;
    int         sections;
    int         seekable;
}

/+
 + The SF_FORMAT_INFO struct is used to retrieve information about the sound
 + file formats libsndfile supports using the sf_command() interface.
 +
 + Using this interface will allow applications to support new file formats
 + and encoding types when libsndfile is upgraded, without requiring
 + re-compilation of the application.
 +
 + Please consult the libsndfile documentation (particularly the information
 + on the sf_command() interface) for examples of its use.
 +/

struct SF_FORMAT_INFO
{   
    int         format;
    char*       name;
    char*       extension;
}

/+
 + Enums and typedefs for adding dither on read and write.
 + See the html documentation for sf_command(), SFC_SET_DITHER_ON_WRITE
 + and SFC_SET_DITHER_ON_READ.
 +/

enum
{   
    SFD_DEFAULT_LEVEL   = 0,
    SFD_CUSTOM_LEVEL    = 0x40000000,

    SFD_NO_DITHER       = 500,
    SFD_WHITE           = 501,
    SFD_TRIANGULAR_PDF  = 502
}

struct SF_DITHER_INFO
{   
    int         type;
    double      level;
    char*       name;
}

/+
 + Struct used to retrieve information about a file embedded within a
 + larger file. See SFC_GET_EMBED_FILE_INFO.
 +/

struct SF_EMBED_FILE_INFO
{   
    sf_count_t  offset;
    sf_count_t  length;
}


//  Structs used to retrieve music sample information from a file.

enum
{
    // The loop mode field in SF_INSTRUMENT will be one of the following.
    SF_LOOP_NONE = 800,
    SF_LOOP_FORWARD,
    SF_LOOP_BACKWARD,
    SF_LOOP_ALTERNATING
}

struct SF_INSTRUMENT
{   
    int gain;
    byte basenote, detune;
    byte velocity_lo, velocity_hi;
    byte key_lo, key_hi;
    int loop_count;

    struct __loops
    {   int mode;
        uint start;
        uint end;
        uint count;
    }

    __loops[16] loops;
}


// Struct used to retrieve loop information from a file.
struct SF_LOOP_INFO
{
    short   time_sig_num;  // any positive integer > 0
    short   time_sig_den;  // any positive power of 2 > 0
    int     loop_mode;     // see SF_LOOP enum

    int     num_beats;     /+ this is NOT the amount of quarter notes !!!
                              a full bar of 4/4 is 4 beats
                              a full bar of 7/8 is 7 beats +/

    float   bpm;           /+ suggestion, as it can be calculated using other
                              fields (file's length, file's sampleRate and
                              our time_sig_den). bpms are always the amount
                              of _quarter notes_ per minute +/

    int root_key;          // MIDI note, or -1 for None
    int[6] future;
}


/+
 + Struct used to retrieve broadcast (EBU) information from a file. 
 + Strongly (!) based on EBU "bext" chunk format used in Broadcast WAVE.
 +/
struct SF_BROADCAST_INFO
{   
    byte[256]       description;
    byte[32]        originator;
    byte[32]        originator_reference;
    byte[10]        origination_date;
    byte[8]         origination_time;
    int             time_reference_low;
    int             time_reference_high;
    short           version_;   // XXX changed from version
    byte[64]        umid;
    byte[190]       reserved;
    uint            coding_history_size ;
    byte[256]       coding_history;
}


extern(C) alias sf_count_t function(void*) sf_vio_get_filelen;
extern(C) alias sf_count_t function(sf_count_t, int, void*) sf_vio_seek;
extern(C) alias sf_count_t function(void*, sf_count_t, void*) sf_vio_read;
extern(C) alias sf_count_t function(void*, sf_count_t, void*) sf_vio_write;
extern(C) alias sf_count_t function(void*) sf_vio_tell;

struct SF_VIRTUAL_IO
{   
    sf_vio_get_filelen  get_filelen;
    sf_vio_seek         seek;
    sf_vio_read         read;
    sf_vio_write        write;
    sf_vio_tell         tell;
}

private void loadsndfile(SharedLib lib)
{
    bindFunc(sf_open)("sf_open", lib);
    bindFunc(sf_open_fd)("sf_open_fd", lib);
    bindFunc(sf_open_virtual)("sf_open_virtual", lib);
    bindFunc(sf_error)("sf_error", lib);
    bindFunc(sf_strerror)("sf_strerror", lib);
    bindFunc(sf_error_number)("sf_error_number", lib);
    bindFunc(sf_perror)("sf_perror", lib);
    bindFunc(sf_error_str)("sf_error_str", lib);
    bindFunc(sf_command)("sf_command", lib);
    bindFunc(sf_format_check)("sf_format_check", lib);
    bindFunc(sf_seek)("sf_seek", lib);
    bindFunc(sf_set_string)("sf_set_string", lib);
    bindFunc(sf_get_string)("sf_get_string", lib);
    bindFunc(sf_read_raw)("sf_read_raw", lib);
    bindFunc(sf_write_raw)("sf_write_raw", lib);
    bindFunc(sf_readf_short)("sf_readf_short", lib);
    bindFunc(sf_writef_short)("sf_writef_short", lib);
    bindFunc(sf_readf_int)("sf_readf_int", lib);
    bindFunc(sf_writef_int)("sf_writef_int", lib);
    bindFunc(sf_readf_float)("sf_readf_float", lib);
    bindFunc(sf_writef_float)("sf_writef_float", lib);
    bindFunc(sf_readf_double)("sf_readf_double", lib);
    bindFunc(sf_writef_double)("sf_writef_double", lib);
    bindFunc(sf_read_short)("sf_read_short", lib);
    bindFunc(sf_write_short)("sf_write_short", lib);
    bindFunc(sf_read_int)("sf_read_int", lib);
    bindFunc(sf_write_int)("sf_write_int", lib);
    bindFunc(sf_read_float)("sf_read_float", lib);
    bindFunc(sf_write_float)("sf_write_float", lib);
    bindFunc(sf_read_double)("sf_read_double", lib);
    bindFunc(sf_write_double)("sf_write_double", lib);
    bindFunc(sf_close)("sf_close", lib);
    bindFunc(sf_write_sync)("sf_write_sync", lib);
}

GenericLoader libsndfile;
static this()
{
    libsndfile.setup(
            "libsndfile.dll",
            "libsndfile.so, libsndfile.so.1",
            "",
            &loadsndfile);
}

extern(C):

/+
 + Open the specified file for read, write or both. On error, this will
 + return a NULL pointer. To find the error number, pass a NULL SNDFILE
 + to sf_perror() or sf_error_str().
 + All calls to sf_open() should be matched with a call to sf_close().
 +/

typedef SNDFILE* function(char* path, int mode, SF_INFO* sfinfo) pfsf_open;
pfsf_open sf_open;

/+
 + Use the existing file descriptor to create a SNDFILE object. If close_desc
 + is TRUE, the file descriptor will be closed when sf_close() is called. If
 + it is FALSE, the descritor will not be closed.
 + When passed a descriptor like this, the library will assume that the start
 + of file header is at the current file offset. This allows sound files within
 + larger container files to be read and/or written.
 + On error, this will return a NULL pointer. To find the error number, pass a
 + NULL SNDFILE to sf_perror() or sf_error_str().
 + All calls to sf_open_fd() should be matched with a call to sf_close().
 +/

typedef SNDFILE* function(int fd, int mode, SF_INFO* sfinfo, int close_desc)
    pfsf_open_fd;
typedef SNDFILE* function(SF_VIRTUAL_IO* sfvirtual, int mode, SF_INFO* sfinfo,
        void* user_data) pfsf_open_virtual;

pfsf_open_fd sf_open_fd;
pfsf_open_virtual sf_open_virtual;

/+
 + sf_error() returns a error number which can be translated to a text
 + string using sf_error_number().
 +/

typedef int function(SNDFILE* sndfile) pfsf_error;
pfsf_error sf_error;

/+
 + sf_strerror() returns to the caller a pointer to the current error message
 + for the given SNDFILE.
 +/

typedef char* function(SNDFILE* sndfile) pfsf_strerror;
pfsf_strerror sf_strerror;

/+
 + sf_error_number() allows the retrieval of the error string for each
 + internal error number.
 +/

typedef char* function(int errnum) pfsf_error_number;
pfsf_error_number sf_error_number;

/+
 + The following three error functions are deprecated but they will remain in
 + the library for the forseeable future. The function sf_strerror() should be
 + used in their place.
 +/

typedef int function(SNDFILE* sndfile) pfsf_perror;
typedef int function(SNDFILE* sndfile, char* str, size_t len) pfsf_error_str;

pfsf_perror sf_perror;
pfsf_error_str sf_error_str;

/+
 + Return TRUE if fields of the SF_INFO struct are a valid combination of
 + values.
 +/

typedef int function(SNDFILE* sndfile, int command, void* data, int datasize)
    pfsf_command;
pfsf_command sf_command;

/+
 + Return TRUE if fields of the SF_INFO struct are a valid combination of
 + values.
 +/

typedef int function(SF_INFO* info) pfsf_format_check;
pfsf_format_check sf_format_check;

/+
 + Seek within the waveform data chunk of the SNDFILE. sf_seek() uses
 + the same values for whence (SEEK_SET, SEEK_CUR and SEEK_END) as
 + stdio.h function fseek().
 + An offset of zero with whence set to SEEK_SET will position the
 + read / write pointer to the first data sample.
 + On success sf_seek returns the current position in (multi-channel)
 + samples from the start of the file.
 + Please see the libsndfile documentation for moving the read pointer
 + separately from the write pointer on files open in mode SFM_RDWR.
 + On error all of these functions return -1.
 +/

typedef sf_count_t function(SNDFILE* sndfile, sf_count_t frames, int whence)
    pfsf_seek;
pfsf_seek sf_seek;

/+
 + Functions for retrieving and setting string data within sound files.
 + Not all file types support this features; AIFF and WAV do. For both
 + functions, the str_type parameter must be one of the SF_STR_* values
 + defined above.
 + On error, sf_set_string() returns non-zero while sf_get_string()
 + returns NULL.
 +/

typedef int function(SNDFILE* sndfile, int str_type, char* str)
    pfsf_set_string;
typedef char* function(SNDFILE* sndfile, int str_type) pfsf_get_string;

pfsf_set_string sf_set_string;
pfsf_get_string sf_get_string;

// Functions for reading/writing the waveform data of a sound file.

typedef sf_count_t function(SNDFILE* sndfile, void* ptr, sf_count_t bytes)
    pfsf_read_raw;
typedef sf_count_t function(SNDFILE* sndfile, void* ptr, sf_count_t bytes)
    pfsf_write_raw;

pfsf_read_raw sf_read_raw;
pfsf_write_raw sf_write_raw;

/+
 + Functions for reading and writing the data chunk in terms of frames.
 + The number of items actually read/written = frames * number of channels.
 +     sf_xxxx_raw      read/writes the raw data bytes from/to the file
 +     sf_xxxx_short    passes data in the native short format
 +     sf_xxxx_int      passes data in the native int format
 +     sf_xxxx_float    passes data in the native float format
 +     sf_xxxx_double   passes data in the native double format
 + All of these read/write function return number of frames read/written.
 +/

typedef sf_count_t function(SNDFILE* sndfile, short* ptr, sf_count_t frames)
    pfsf_readf_short;
typedef sf_count_t function(SNDFILE* sndfile, short* ptr, sf_count_t frames)
    pfsf_writef_short;

typedef sf_count_t function(SNDFILE* sndfile, int* ptr, sf_count_t frames)
    pfsf_readf_int;
typedef sf_count_t function(SNDFILE* sndfile, int* ptr, sf_count_t frames)
    pfsf_writef_int;

typedef sf_count_t function(SNDFILE* sndfile, float* ptr, sf_count_t frames)
    pfsf_readf_float;
typedef sf_count_t function(SNDFILE* sndfile, float* ptr, sf_count_t frames)
    pfsf_writef_float;

typedef sf_count_t function(SNDFILE* sndfile, double* ptr, sf_count_t frames)
    pfsf_readf_double;
typedef sf_count_t function(SNDFILE* sndfile, double* ptr, sf_count_t frames)
    pfsf_writef_double;

pfsf_readf_short sf_readf_short;
pfsf_writef_short sf_writef_short;
pfsf_readf_int sf_readf_int;
pfsf_writef_int sf_writef_int;
pfsf_readf_float sf_readf_float;
pfsf_writef_float sf_writef_float;
pfsf_readf_double sf_readf_double;
pfsf_writef_double sf_writef_double;

/+
 + Functions for reading and writing the data chunk in terms of items.
 + Otherwise similar to above.
 + All of these read/write function return number of items read/written.
 +/

typedef sf_count_t function(SNDFILE* sndfile, short* ptr, sf_count_t items)
    pfsf_read_short;
typedef sf_count_t function(SNDFILE* sndfile, short* ptr, sf_count_t items)
    pfsf_write_short;

typedef sf_count_t function(SNDFILE* sndfile, int* ptr, sf_count_t items)
    pfsf_read_int;
typedef sf_count_t function(SNDFILE* sndfile, int* ptr, sf_count_t items)
    pfsf_write_int;

typedef sf_count_t function(SNDFILE* sndfile, float* ptr, sf_count_t items)
    pfsf_read_float;
typedef sf_count_t function(SNDFILE* sndfile, float* ptr, sf_count_t items)
    pfsf_write_float;

typedef sf_count_t function(SNDFILE* sndfile, double* ptr, sf_count_t items)
    pfsf_read_double;
typedef sf_count_t function(SNDFILE* sndfile, double* ptr, sf_count_t items)
    pfsf_write_double;

pfsf_read_short sf_read_short;
pfsf_write_short sf_write_short;
pfsf_read_int sf_read_int;
pfsf_write_int sf_write_int;
pfsf_read_float sf_read_float;
pfsf_write_float sf_write_float;
pfsf_read_double sf_read_double;
pfsf_write_double sf_write_double;

/+
 + Close the SNDFILE and clean up all memory allocations associated with this
 + file.
 + Returns 0 on success, or an error number.
 +/

typedef int function(SNDFILE* sndfile) pfsf_close;
pfsf_close sf_close;

/+
 + If the file is opened SFM_WRITE or SFM_RDWR, call fsync() on the file
 + to force the writing of data to disk. If the file is opened SFM_READ
 + no action is taken.
 +/

typedef void function(SNDFILE* sndfile) pfsf_write_sync;
pfsf_write_sync sf_write_sync;

