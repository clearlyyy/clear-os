; BOOT-LOADER

org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

; FAT12 header
jmp short start
nop

bdb_oem:                   db 'MSWIN4.1'         ; 8 bytes
bdb_bytes_per_sector:      dw 512        
bdb_sectors_per_cluster:   db 1
bdb_reserved_sectors:      dw 1
bdb_fat_count:             db 2
bdb_dir_entries_count:     dw 0E0h
bdb_total_sectors:         dw 2880               ; 2880 * 512 = 1.44MB
bdb_media_descriptor_type: db 0F0h               ; 3.5 inch floppy disk
bdb_sector_per_fat:        dw 9                  ; 9 sectors/fat
bdb_sectors_per_track      dw 18
bdb_heads:                 dw 2
bdb_hidden_sectors         dd 0
bdb_large_sector_count:    dd 0

; extended boot record
ebr_drive_number:          db 0                  ; 0x00 floppy, 0x80 hdd
                           db 0                  ; reserved
ebr_signature:             db 29h
ebr_volume_id:             db 12h, 34h, 56h, 78h ; serial number
ebr_volume_label:          db 'CLEAROS    '      ; 11 bytes
ebr_system_id:             db 'FAT12   '         ; 8 bytes


start:
    jmp main

; print a string to the screen
; Params:
;  - ds:si points to string
puts:
    ; save registers we will modify
    push si
    push ax

.loop:
    lodsb           ; loads next character in al
    or al, al,      ; verify if next character is null?
    jz .done
    

    mov ah, 0x0e
    mov bh, 0
    int 0x10

    jmp .loop

.done:
    pop ax
    pop si 
    ret

main:

    ; setup data segments
    mov ax, 0
    mov ds, ax
    mov es, ax

    ;setup stack
    mov ss, ax
    mov sp, 0x7C00

    ; read something from floppy disk
    mov [ebr_drive_number], dl
    mov ax, 1                 ; LBA=1, second sector from disk
    mov cl, 1                 ; 1 sector to read
    mov bx, 0x7E00            ; data should be after the bootloader
    call disk_read


    ; print message
    mov si, msg_hello
    call puts

    cli                       ; disable interupts.
    hlt

; Error handlers
floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h         ; wait for keypress
    jmp 0FFFFh:0    ; jump to beggining of BIOS, should reboot
.halt:
    cli             ; disable interupts so CPU cant get out of 'halt' state
    hlt



; Disk routines

; Convert an LBA address to a CHS Address
; Parameters:
; - ax: LBA address
; Returns:
; - cx [bits 0-5]: sector number
; - cx [bits 6-15]: cylinder
; - dh: head
lba_to_chs:

    push ax
    push dx

    xor dx, dx                               ; dx = 0;
    div word [bdb_sectors_per_track]         ; ax = LBA / SectorsPerTrack
                                             ; dx = LBA % SectorsPerTrack

    inc dx                                   ; dx = (LBA % SectorsPerTrack + 1) = sector
    mov cx, dx                               ; cx = sector

    xor dx, dx                               ; dx = 0
    div word [bdb_heads]                     ; ax = (LBA / SectorsPerTrack) / Heads = cylinder
                                             ; dx = (LBA / SectorsPerTrack) % Heads = head
    mov dh, dl                               ; dh = head
    mov ch, al                               ; ch = cylinder (lower 8 bits)
    shl ah, 6
    or cl, ah                                ; put upper 2 bits of cylinder

    pop ax
    mov dl, al                               ; Restore DL
    pop ax
    ret


; Reads sectors from a disk
; Parameters:
; - ax: LBA Address
; - cl: number of sectors to read (up to 128)
; - dl: drive number
; - es:bx: memory address where to store read data
disk_read:

    ; save registers we will modify
    push ax
    push bx
    push cx
    push dx
    push di

    push cx                     ; temporarily save CL (number of sectors to read)
    call lba_to_chs             ; compute CHS
    pop ax                      ; AL = number of sectors to read

    mov ah, 02h                 
    mov di, 3                   ; retry count (3)

.retry:
    pusha                       ; save all registers, we dont know what the bios modifies
    stc                         ; set carry flag, some BIOS'es dont set it
    int 13h                     ; carry flag cleared = success
    jnc .done                   ; jump if carry not set

    ;read failed
    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    ; after all attempts
    jmp floppy_error

.done:
    popa
    ; restore registers modified 
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; Reset disk controller
; Parameters:
; - dl: drive number
disk_reset
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret

msg_hello: db 'Hello World', ENDL, 0
msg_read_failed: db 'Failed to read from disk!', ENDL, 0


times 510-($-$$) db 0
dw 0AA55h