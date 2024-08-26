section .text
    global _start

_start:
    xchg r11, r11         ; This is the single assembly instruction

    ; Exit the program
    mov eax, 60  ; syscall number for exit in x86-64 Linux
    xor edi, edi ; status 0
    syscall      ; invoke operating system to exit
