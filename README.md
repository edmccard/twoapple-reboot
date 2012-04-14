# twoapple-reboot

**An Apple II emulator for Linux, written in the D programming language**

twoapple-reboot is a fork of [twoapple](https://code.google.com/p/twoapple)
updated to work with the latest version of D on both 32- and 64-bit Linux.

### Building

twoapple-reboot works with dmd 2.058; I haven't tried it with ldc/gdc.

It depends on [gtkd](http://www.dsource.org/projects/gtkd) and [Derelict2](http://www.dsource.org/projects/derelict)

Build by running `make` in the `src` directory; if the dependencies aren't installed to standard import/lib paths, you can do
```
make GTKD=/path/to/gtkd DERELICT=/path/to/Derelict2
```

### Testing

There are tests for the 6502/65C02 emulation:

```
cd test
rdmd runtests.d --help
```

### Use
For now, see README.orig

### TODO

+ use new D2 features
+ better UI
+ cassette emulation
+ more peripherals
