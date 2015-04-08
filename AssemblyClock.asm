 .include "m32def.inc"
 .equ FREQ = 11059200 ; frequency in hertz
 .equ USART_BAUDRATE=19200
 .equ BAUD_PRESCALE=(((FREQ / (USART_BAUDRATE * 16))) - 1)
 .equ counter_flag = 0
 .equ LCD=PORTD
 .equ LCD_DD=DDRD
 .equ ENABLE=2
 .equ RS=3

 .def tmp = r16
 .def counter = r17
 .def int_flags = r18
 .def arg=r19
 .def counter1=r20
 .def counter2=r21
 .def h=r22
 .def m=r23
 .def s=r24

 .dseg
 number: .byte 4

 .cseg

 .org 0x0
 rjmp main

 .org OC1Aaddr
 rjmp timer1


 main:
	ldi tmp, low(RAMEND)	; reset stack pointer
	out SPL, tmp
	ldi tmp, high(RAMEND)
	out SPH, tmp

	rcall delay_some_ms ; wait for display to be ready
	rcall delay_some_ms
	rcall delay_some_ms

	clr tmp				; set display as output
	out LCD, tmp
	ser tmp
	out LCD_DD, tmp

	rcall init_lcd		; init lcd

	ldi tmp, (1<<CTC1) | (1<<CS12) | (1<<CS10) | (1<<WGM12)	; enable timer with prescaler 1024
	out TCCR1B, tmp

	ldi tmp, high((freq/1024))
	out OCR1AH, tmp
	ldi tmp, low((freq/1024))
	out OCR1AL, tmp

	ldi tmp, 1<<OCIE1A	; enable timer compare interrupt
	out TIMSK, tmp

	clr tmp
	out TCNT1H, tmp
	out TCNT1L, tmp
	
	clr counter
	
	ldi h, 3
	ldi m, 4
	ldi s, 3

	sei

loop:
	sbrs int_flags, counter_flag
	rjmp loop
	inc counter
	rcall update_number
	cbr int_flags, 1<<counter_flag
	rjmp loop

timer1:
	sbr int_flags, 1<<counter_flag
	reti

init_lcd:
	rcall init_4bitmode
	ldi arg, 0x28
	rcall send_ins
	ldi arg, 0x0E
	rcall send_ins
	ldi arg, 0x01
	rcall send_ins
	ldi arg, 0x06
	rcall send_ins
	ret
	
init_4bitmode:
	ldi tmp, 0x30
	out LCD, tmp
	rcall clock_in
	rcall delay_some_ms
	ldi tmp, 0x30
	out LCD, tmp
	rcall clock_in
	rcall delay_some_ms
	ldi tmp, 0x30
	out LCD, tmp
	rcall clock_in
	rcall delay_some_ms
	ldi tmp, 0x20
	out LCD, tmp
	rcall clock_in
	rcall delay_some_ms
	ret
	
send_ins:
	push arg
	andi arg, 0xF0
	out LCD, arg
	rcall clock_in
	pop arg
	swap arg
	andi arg, 0xF0
	out LCD, arg
	rcall clock_in
	rcall delay_some_ms
	ret
	
show_char:
	push arg
	andi arg, 0xf0   
	sbr arg, (1 << RS)
	out LCD, arg
	rcall clock_in
	pop arg
	swap arg
	andi arg, 0xf0
	sbr arg, (1 << RS)
	out LCD, arg
	rcall clock_in
	ret
	
	
clock_in:
	cbi LCD, ENABLE
	sbi LCD, ENABLE
	rcall delay_one_ish_ms
	cbi LCD, ENABLE
	ret

delay_some_ms:
	clr counter1
delay_1:
	clr counter2
delay_2:
	dec counter2
	brne delay_2
	dec counter1
	brne delay_1
	ret

delay_one_ish_ms:
	ldi counter1, 40
delay_one_1:
	clr counter2
delay_one_2:
	dec counter2
	brne delay_one_2
	dec counter1
	brne delay_1
	ret

update_number:
	inc s
	cpi s, 60
	brne display_time
	clr s
	inc m
	cpi m, 60
	brne display_time
	clr m
	inc h
display_time:
	ldi arg, 0x80
	rcall send_ins
	mov arg, h
	rcall show_ascii
	ldi arg, ':'
	rcall show_char
	mov arg, m
	rcall show_ascii
	ldi arg, ':'
	rcall show_char
	mov arg, s
	rcall show_ascii
	
	ret

show_ascii:
	clr tmp
tens:
	cpi arg, 10
	brlo end_tens
	inc tmp
	subi arg, 10
	rjmp tens

end_tens:
	subi tmp, -48
	push arg
	mov arg, tmp
	rcall show_char
	pop arg
	subi arg, -48
	rcall show_char
	ret
	
init_usart:
	ldi tmp, (1 << RXEN) | (1 << TXEN) ; set send and receive bit
	out UCSRB, tmp

	ldi tmp, (1 << URSEL) | (1 << UCSZ0) | (1 << UCSZ1)
	out UCSRC, tmp

	ldi tmp, high(BAUD_PRESCALE)
	out UBRRH, tmp
	ldi tmp, low(BAUD_PRESCALE)
	out UBRRL, tmp
	ret
	
usart_recv:
	sbis UCSRA, RXC
	rjmp usart_in
	in arg, UDR
	ret
	
usart_send:
	sbis UCSRA, UDRE
	rjmp usart_out
	out UDR, arg
	ret
