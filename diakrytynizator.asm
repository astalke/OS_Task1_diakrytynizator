; Systemy Operacyjne, I zadanie zaliczeniowe: "Diakrytynizator"
; Autor: Andrzej Stalke

; Stałe wykorzystywane w programie.
; Stałe wejścia-wyjścia
STDIN:        equ     0               ; Deskryptor standardowego wejścia.
STDOUT:       equ     1               ; Deskryptor standardowego wyjścia.
EOF:          equ     0x100           ; Stała informująca o napotkaniu EOF,
                                      ; musi spełniać: 0xFF < EOF < 0xFFFF

; Numery wykorzystywanych funkcji systemowych.
SYS_READ:     equ     0               ; Numer funkcji systemowej read.
SYS_WRITE:    equ     1               ; Numer funkcji systemowej write.
SYS_EXIT:     equ     60              ; Numer funkcji systemowej exit.

; Stałe logiki programu.
MODULO:       equ     0x10FF80        ; Stała którą modulujemy.
EXIT_SUCCESS: equ     0               ; Stała informująca o powodzeniu.
EXIT_FAILURE: equ     1               ; Stała informująca o niepowodzeniu.
BUFFER_SIZE:  equ     4096            ; Rozmiar w bajtach bufora STDIN.
STDOUT_FLUSH: equ     4092            ; Liczba bajtów po której opróżniamy.

        global  _start
        section .text
; Konwertuje tablicę znaków do nieujemnej liczby całkowitej modulo MODULO
; Zakłada, że przekazana liczba ma dowolny rozmiar (może być większa od 2^64).
; Argumenty: rdi - wskaźnik na tablicę charów zakończoną zerem.
; Wyjście: rax - nieujemna wartość liczbowa modulo MODULO. Wartość większa od
;                MODULO oznacza błąd.
; Modyfikuje rejestry: rax, rcx, rdx, rsi, rdi, FLAGS
cs2i:
        mov rsi, MODULO             ; Nasz dzielnik.
        xor rax, rax                ; Zerowanie rax.
        xor rcx, rcx                ; W rcx trzymamy znak.
.loop:
        mov cl, [rdi]               ; Pobieramy pierwszy bajt do analizy.
        test cl, cl                 ; Sprawdzamy, czy trafiliśmy na NULL.
        jz .exit_success
        cmp cl, '9'                 ; Czy znak jest mniejszy jub równy '9'?
        ja .exit_failure            ; Nie jest - błąd.
        cmp cl, '0'                 ; Czy znak jest większy lub równy '0'?
        jb .exit_failure            ; Nie jest - błąd.
        sub cl, '0'                 ; Konwertujemy znak do cyfry.
        mov rdx, 10
        mul rdx                     ; Przesuwamy wynik o pozycję dziesiętną.
        xor rdx, rdx                ; rdx powinno być 0, ale na wszelki wypadek
        add rax, rcx                ; Wrzucamy cyfrę jedności.
        div rsi                     ; Liczymy modulo
        mov rax, rdx
        inc rdi
        jmp .loop
.exit_failure:
        mov rax, -1
.exit_success:
        ret

; Zwraca pierwszy nieprzeczytany bajt z stdin. Zwraca EOF w przypadku napotkania
; EOF, w przypadku błędu zwraca -2
; Modyfikuje rejestry: rax, rcx, rdi, rsi, rdx, r11, FLAGS
; Wynik: Kod bajtu w przypadku powodzenia, EOF jeśli napotkamy EOF.
; W przypadku błędu: rax == -errno
take_char:
        mov     rdi, qword [stdin_counter]  ; Indeks nieprzeczytanego bajtu.
        mov     rsi, qword [stdin_size]     ; Liczba bajtów w buforze.
        cmp     rdi, rsi            ; Sprawdzamy, czy licznik na coś wskazuje.
        jb      .counter_ok         ; Są dane w buforze.
        ; Musimy wczytać nowe dane - wołamy read.
        mov     rax, SYS_READ
        mov     rdi, STDIN
        mov     rsi, stdin_buffer
        mov     rdx, BUFFER_SIZE
        syscall                     ; Wołamy sys_read, w rax jest nowe size
        mov     qword [stdin_size], rax ; Aktualizacja rozmiaru.
        cmp     rax, 0              ; Sprawdzamy błędy.
        jz      .exit_eof           ; rax == 0 oznacza EOF.
        jl      .exit_error         ; rax < 0 oznacza błąd.
        xor     rdi, rdi            ; Indeks nieprzeczytanego bajtu jest 0.
.counter_ok:
        xor     rax, rax
        lea     rsi, [stdin_buffer + rdi]   ; Liczymy adres bajtu.
        inc     rdi
        mov     qword [stdin_counter], rdi  ; Aktualizacja licznika.
        mov     al, byte [rsi]      ; Pobieramy wartość z bufora.
        ret
.exit_eof:
        mov     rax, EOF
.exit_error:
        ret
; Oblicza wartość wielomianu diakrytynizującego modulo MODULO.
; rdi - Argument wielomianu.
; rsi - Wskaźnik na tablicę argumentów.
; rdx - Liczba argumentów.
; Modyfikowane rejestry: rax, rcx, rdx, rdi, rsi, r8
calculate_polynomial:
        xor     rax, rax            ; W rax trzymamy wynik.
        mov     rcx, rdx            ; rcx służy nam za iterator pętli
        mov     r8, MODULO          ; Trzyma dzielnik.
.loop:
        mul     rdi                 ; wynik *= x
        add     rax, qword [rsi + 8 * rcx - 8] ; wynik += arg[i]
        xor     rdx, rdx            ; Na potrzebę dzielenia.
        div     r8                  ; Liczymy modulo.
        mov     rax, rdx            
        loop    .loop
        ret

; Opróżnia bufor standardowego wyjścia poprzez wypisanie go na ekran.
; Nie przyjmuje argumentów.
; Modyfikuje: rax, rcx, rdx, rdi, rsi, r11
flush:
        mov     rax, SYS_WRITE      ; Wywołujemy sys_write na buforze.
        mov     rdi, STDOUT         ; Piszemy na standardowe wyjście.
        mov     rsi, stdout_buffer  ; Z bufora.
        mov     rdx, qword [stdout_counter]
        syscall
        cmp     rax, 0              ; Ujemne wartości oznaczają błąd.
        jl      .write_fail
        xor     rdi, rdi
        mov     qword[stdout_counter], rdi  ; Czyszczenie bufora.
        ret
.write_fail:
        mov     rax, SYS_EXIT       ; Zamykamy program bezpośrednio
        mov     rdi, EXIT_FAILURE   ; ponieważ exit_with_failure
        syscall                     ; wywołuje flush i powstaje pętla

; Umieszcza znak unicode do bufora STDOUT kodowaniem UTF-8.
; rdi - kod unicode
; Modyfikuje: rax, rcx, rdx, rdi, rsi, r8, r9, r11
put_unicode:
        ; rsi - wskaźnik na bufor wyjściowy
        ; r9 - licznik powyższego bufora
        mov     r11, rdi            ; Kopiujemy dane do r11.        
        mov     rsi, stdout_buffer  ; Bufor do pisania
        mov     r9, qword [stdout_counter] ; Licznik bufora.
        cmp     rdi, 0x10000
        jae     .4B                 ; Wymagane 4 bajty do zapisu.
        cmp     rdi, 0x800         
        jae     .3B                 ; Wymagane 3 bajty do zapisu.
        cmp     rdi, 0x80 
        jae     .2B                 ; Wymagane 2 bajty do zapisu.
        ; ASCII
        mov     byte [rsi + r9], dil; Przenosimy do bufora uzyskany bajt.
        inc     r9
        jmp     .end
.4B:    
        inc     rcx                 ; Zwiększamy licznik bitów.
        shr     r11, 6              ; Obcinamy bity, które są w dalszych bajtach
.3B:
        inc     rcx                 ; Zwiększamy licznik bitów.
        shr     r11, 6              ; Obcinamy bity, które są w dalszych bajtach
.2B:
        inc     rcx                 ; Zwiększamy licznik bitów.
        shr     r11, 6              ; Obcinamy bity, które są w dalszych bajtach
.done:
        ; Generujemy bity kontrolne.
        ; Dla 4B: ((0x07 >> 3) xor 0xF) << 4 == (0 xor 0x0F) << 4 == 0xF0
        ; Dla 3B: ((0x07 >> 2) xor 0xF) << 4 == (1 xor 0x0F) << 4 == 0xE0
        ; Dla 2B: ((0x07 >> 1) xor 0xF) << 4 == (3 xor 0x0F) << 4 == 0xC0
        mov     rax, 0x07           ; Bitowo: 0000.0111
        shr     al, cl              ; Przesuwamy al o odpowiednią liczbę bitów.
        xor     al, 0x0F            
        shl     al, 4               ; Teraz al zawiera bity kontrolne.
        ; rax - bity kontrolne, r11 - bity danych
        or      rax, r11            ; Łączymy kontrolne z danymi.
        mov     byte [rsi + r9], al  ; Przenosimy do bufora uzyskany bajt.
        inc     r9
        test    rcx, rcx
        jz      .end
.loop:
        mov     r11, rdi            ; Kopiujemy dane.
        dec     cl                  ; Chcemy obliczyć przesunięcie bitowe.
        mov     al, 0x06
        mul     cl                  ; 0 <= rcx <= 2, iloczyn nie przekroczy 12
        inc     cl
        xchg    cl, al              ; shr przyjmuje jako argument tylko cl
        shr     r11, cl             ; Przesuwamy r11 o odpowiednią liczbę bitów.
        and     r11, 0x3F           ; Obcinamy niepotrzebne bity.
        mov     cl, al              ; Przywracamy licznik pętli.
        or      r11, 0x80           ; Ustawiamy bit kontrolny.
        mov     byte [rsi + r9], r11b; Ustawiamy bajt.
        inc     r9
        loop    .loop
.end:
        mov     qword [stdout_counter], r9           ; Aktualizacja licznika
        cmp     r9, STDOUT_FLUSH    ; Czy trzeba wyczyścić bufor?
        jb      .no_flush           ; Nie ma potrzeby flushowania.
        and     rsp, 0xFFFFFFFFFFFFFFF0 ; Wyrównanie do 16 
        call    flush
        or      rsp, 0x0000000000000008 ; Przywracamy stos.
.no_flush:
        ret


; Punkt wejścia programu.
_start:
        pop     r12                 ; Pobieramy argc z stosu.
        cmp     r12, 2              ; Sprawdzamy, czy są argumenty.
        jb      .exit_failure       ; Nie ma argumentów - zwróć błąd.
        mov     r13, rsp            ; argv
        add     r13, 8              ; Omijamy argv[0]
        dec     r12                 ; Omijamy argv[0] 
        mov     rbp, rsp            ; Zapamiętujemy początek stosu.
        mov     rax, 8              ; Liczymy potrzebne miejsce na argumenty
        mul     r12
        sub     rsp, rax            ; Rezerwujemy miejsce na argumenty.
        lea     r14, [rbp - 8]      ; Wskaźnik na pierwsze wolne pole w tablicy.
        and     rsp, 0xFFFFFFFFFFFFFFF0; ; Wyrównujemy rsp do 16
 
        ; Poniższa część kodu odpowiada za przetworzenie argumentów.
        ; r12 - Liczba argumentów.
        ; r13 - Wskaźnik na wskaźnik na pierwszy bajt przetwarzanego stringa.
        ; r14 - Wskaźnik na pierwsze wolne miejsce w tablicy przetworzonych.
.parse_arguments_loop:              ; Parsowanie argumentów.
        mov     rdi, qword [r13]    ; Wskaźnik na pierwszy bajt stringa.
        add     r13, 8              ; Przesuwamy wskaźnik na kolejny element.
        test    rdi, rdi            ; Sprawdzamy, czy NULL.
        jz      .read_unicode       ; Mamy NULL, koniec parsowania.
        call    cs2i                ; Konwertujemy tekst do liczby.
        cmp     rax, MODULO
        jae     .exit_failure       ; Niepoprawny argument.
        mov     qword [r14], rax    ; Zapisujemy wynik do tablicy.
        add     r14, 8 
        jmp     .parse_arguments_loop

        ; W poniższej sekcji argv przestaje nam być potrzebne.
.read_unicode:                      ; Przetwarzanie unicode z wejścia.
        lea     r13, [rbp - 8]      ; Wskaźnik na początek tablicy argumentów.

        ; Pętla wczytująca unicode z wejścia. 
        ; r12 - Liczba argumentów.
        ; r13 - Wskaźnik na początek tablicy argumentów.
        ; r14 - Wynikowy kod znaku.
        ; rbx - Liczba wykorzystanych dodatkowych bajtów do zapisu.
.unicode_loop:
        xor     rbx, rbx            ; Zerujemy liczbę wykorzystanych bajtów.
        call    take_char           ; Pobieramy pierwszy znak z STDIN
        cmp     rax, EOF            
        je      .exit_success       ; rax == EOF oznacza zakończenie pracy.
        ja      .exit_failure       ; (unsigned)rax > EOF oznacza błąd (ujemny)
        mov     r14, rax
        test    r14, 0x80           ; Czy zapalony jest ósmy bit (2^7)?
        jz      .ascii              ; Kod jest zwykłym kodem ASCII.
        test    r14, 0x40           ; Czy zapalony jest siódmy bit (musi być)?
        jz      .exit_failure       ; Niepoprawny kod unicode.
        test    r14, 0x20
        jz      .one_arg            ; Bajt ma postać: 110xxxxx
        test    r14, 0x10
        jz      .two_args           ; Bajt ma postać: 1110xxxx
        test    r14, 0x08
        jz      .three_args         ; Bajt ma postać: 11110xxx
        jmp     .exit_failure       ; Kod wymagałby ponad 4 bajtów.
.three_args:
        inc     rbx                 ; W połączeniu z kolejnymi, rbx wyjdzie 3.
        and     r14, 0x07           ; Zostawiamy tylko znaczące bity.
.two_args:
        inc     rbx                 ; W połączeniu z kolejnymi, rbx wyjdzie 2.
        and     r14, 0x0F           ; Zostawiamy tylko znaczące bity.
.one_arg:
        inc     rbx                 ; W połączeniu z kolejnymi, rbx wyjdzie 1.
        and     r14, 0x1F           ; Zostawiamy tylko znaczące bity.

        mov     rcx, rbx            ; Ustawiamy licznik pętli.
.loop:
        shl     r14, 6              ; Rezerwujemy miejsce na kolejne bity.
        mov     r15, rcx            ; Zachowujemy licznik pętli.
        call    take_char           ; Pobieramy kolejny bajt z wejścia.
        cmp     rax, EOF            ; Koniec danych to błąd.
        je      .exit_failure
        mov     rcx, r15            ; Przywracamy licznik pętli.
        xor     rax, 0x80           ; Wczytany bajt musi być postaci 10xxxxxx
        test    rax, 0xC0           ; 00xxxxxx and 11000000 == 0
        jnz      .exit_failure      ; Nie zgadzały się 2 pierwsze bity.
        or      r14, rax            ; xxxxx000000 or 00000yyyyyy = xxxxxyyyyyy
        loop    .loop

        ; Sprawdzanie poprawności uzyskanej liczby.
.correctness_check:
        cmp     r14, 0x10FFFF       ; Unicode musi być niewiększy od tego.
        ja      .exit_failure
        cmp     r14, 0x10000        ; Jeśli r14 >= 0x10000, to rbx == 3 (ok)
        jae     .check_passed       ; Nie da się tego zapisać na 2 bajtach.

        cmp     r14, 0x800          ; Jeśli r14 >= 0x800, to rbx == 2
        jae     .used_bytes_ae2

        cmp     r14, 0x80           ; Jeśli r14 >= 0x80, to rbx == 1
        jae     .used_bytes_ae1
        jmp     .exit_failure       ; Niepoprawny zapis.
.used_bytes_ae2:
        dec     rbx                 ; Test niżej sprawdzi poprawność.
.used_bytes_ae1:
        cmp     rbx, 1
        jne     .exit_failure       ; Niepoprawny zapis.
        jmp     .check_passed
        ; Uzyskane Unicode jest poprawne.
.check_passed:
        mov     rdi, r14            ; Argument wielomianu.
        mov     rsi, r13            ; Współczynniki wielomianu.
        mov     rdx, r12            ; Liczba współczynników.
        sub     rdi, 0x80           ; Mamy wywołać w(x - 0x80)
        call    calculate_polynomial
        add     rax, 0x80           ; Mieliśmy policzyć w(x - 0x80) + 0x80
        mov     r14, rax            ; Przywracamy starą wartość.
.ascii:
        mov     rdi, r14
        call    put_unicode         ; Umieszczamy wynik w buforze STDOUT.
        jmp     .unicode_loop



.exit_success:
        call    exit_with_success
.exit_failure:
        call    exit_with_failure

; Opróżnia bufor i zamyka program z kodem błędu EXIT_FAILURE.
; Nie przyjmuje argumentów.
; Modyfikuje: rax, rcx, rdx, rdi, rsi, r11
; Funkcja nie wraca.
exit_with_failure:
        and     rsp, 0XFFFFFFFFFFFFFFF0 ; Wyrównanie do 16 
        call    flush
        or      rsp, 0x0000000000000008 ; Przywracamy stos.
        mov     rax, SYS_EXIT
        mov     rdi, EXIT_FAILURE
        syscall

; Opróżnia bufor i zamyka program z kodem błędu EXIT_SUCCESS.
; Nie przyjmuje argumentów.
; Modyfikuje: rax, rcx, rdx, rdi, rsi, r11
; Funkcja nie wraca.
exit_with_success:
        and     rsp, 0XFFFFFFFFFFFFFFF0 ; Wyrównanie do 16 
        call    flush
        or      rsp, 0x0000000000000008 ; Przywracamy stos.
        mov     rax, SYS_EXIT
        mov     rdi, EXIT_SUCCESS
        syscall

        section .bss
        ; Pamięć wykorzystywana do buforowania danych z STDIN.
stdin_buffer:   resb  BUFFER_SIZE   ; Bufor przechowujący wczytane dane.
stdout_buffer:  resb  BUFFER_SIZE   ; Bufor przechowujący dane do wypisania.
stdin_counter:  resq  1             ; Licznik pierwszego nieprzeczytanego bajtu.
stdin_size:     resq  1             ; Rozmiar aktualnie wczytanych danych.
        ; Pamięć wykorzystywana do buforowania danych z STDOUT.
stdout_counter: resq  1             ; Licznik pierwszego nieużytego bajtu.
