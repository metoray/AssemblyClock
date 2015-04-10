 .include "m32def.inc"
 .equ FREQ = 11059200 ; frequency in hertz
 .equ USART_BAUDRATE=19200
 .equ BAUD_PRESCALE=(((FREQ / (USART_BAUDRATE * 16))) - 1)
 .equ counter_flag = 0
 .equ blink_flag = 1
 .equ update_display_flag = 2
 .equ LCD=PORTD
 .equ LCD_DD=DDRD
 .equ ENABLE=2
 .equ RS=3
 .equ BLINK_ALARM=0
 .equ BLINK_SECONDS=1
 .equ BLINK_MINUTES=2
 .equ BLINK_HOURS=3
 .equ ALARM_VISIBLE=BLINK_ALARM+4
 .equ SECONDS_VISIBLE=BLINK_SECONDS+4
 .equ MINUTES_VISIBLE=BLINK_MINUTES+4
 .equ HOURS_VISIBLE=BLINK_HOURS+4

 .def tmp = r16
 .def counter = r17
 .def int_flags = r18
 .def arg=r19
 .def counter1=r20
 .def counter2=r21
 .def blink=r25

 .dseg
 time: .byte 3

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

	ldi tmp, (1<<CTC1) | (1<<CS12) | (1<<CS10) | (1<<WGM12)	; enable timer with prescaler 1024
	out TCCR1B, tmp

	rcall init_lcd		; init lcd

	ldi tmp, high((freq/1024)/4)
	out OCR1AH, tmp
	ldi tmp, low((freq/1024)/4)
	out OCR1AL, tmp

	ldi tmp, 1<<OCIE1A	; enable timer compare interrupt
	out TIMSK, tmp

	clr tmp
	out TCNT1H, tmp
	out TCNT1L, tmp
	
	rcall init_usart	; init serial communication
	
	clr counter
	
	ldi ZH, high(time)
	ldi ZL, low(time)
	ldi tmp, 4
	st Z+, tmp	;hours
	ldi tmp, 59
	st Z+, tmp	;minutes
	ldi tmp, 55
	st Z+, tmp	;seconds
	
	ldi blink, 0x0
	
	rcall create_character
	
	sei
	

loop:
	sbrs int_flags, counter_flag
	rjmp loop_blink
	
	rcall update_time
	
	cbr int_flags, 1<<counter_flag

loop_blink:
	sbrs int_flags, blink_flag
	rjmp loop_update_display
	
	mov tmp, blink
	swap tmp
	andi tmp, 0xF0
	eor blink, tmp
	com tmp
	andi tmp, 0xF0
	or blink, tmp
	sbr int_flags, 1<<update_display_flag
	
	
	cbr int_flags, 1<<blink_flag
	
loop_update_display:
	sbrs int_flags, update_display_flag
	rjmp loop
	
	rcall display_time
	
	cbr int_flags, 1<<update_display_flag
	
	rjmp loop

timer1:
	push tmp
	in tmp, SREG
	inc counter
	sbrs counter, 0
	sbr int_flags, 1<<blink_flag
	cpi counter, 4
	brne end_timer1
	sbr int_flags, 1<<counter_flag
	clr counter
end_timer1:
	out SREG, tmp
	pop tmp
	reti

update_number:
	ld tmp, -Z
	inc tmp
	cp tmp, arg
	clc
	brne update_number_no_carry
	clr tmp
	sec
update_number_no_carry:
	st Z, tmp
	ret
	

update_time:
	ldi ZH, high(time+3)
	ldi ZL, low(time+3)
	ldi arg, 60
	rcall update_number
	brcc update_time_end
	rcall update_number
	brcc update_time_end
	ldi arg, 24
	rcall update_number
update_time_end:
	sbr int_flags, 1<<update_display_flag
ret

display_time:
	rcall delay_some_ms
	push blink
	ldi ZH, high(time)
	ldi ZL, low(time)
	ldi arg, 0x80
	rcall send_ins
	rcall usart_send
	ldi tmp, 3
display_time_loop:
	ld arg, Z+
	lsl blink
	brcc display_time_loop_blank
	rcall show_ascii
	rcall show_segment
	rjmp display_time_loop_continue
display_time_loop_blank:
	ldi arg, ' '
	rcall show_char
	rcall show_char
	clr arg
	rcall usart_send
	rcall usart_send
display_time_loop_continue:
	dec tmp
	tst tmp
	breq display_time_loop_end
	ldi arg, ':'
	rcall show_char
	rjmp display_time_loop
display_time_loop_end:
	ldi arg, 0x0
	sbrc blink, ALARM_VISIBLE
	rcall show_char
	pop blink
	ldi arg, 0b0111
	sbrc blink, ALARM_VISIBLE
	cbr arg, 0b0001
	rcall usart_send
	clt
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
	rjmp usart_recv
	in arg, UDR
	ret
	
usart_send:
	sbis UCSRA, UDRE
	rjmp usart_send
	out UDR, arg
	ret
	
numbertable: .db 0b1110111, 0b0100100, 0b1011101, 0b1101101, 0b0101110, 0b1101011, 0b1111011, 0b0100101, 0b1111111, 0b1101111
segment_digit:
	push ZL
	push ZH
	cpi arg, 10
	brge segment_error
	ldi ZH, high(numbertable*2)
	ldi ZL, low(numbertable*2)
	add ZL, arg
	clr arg
	adc ZH, arg
	lpm arg, Z
	pop ZH
	pop ZL
	ret
segment_error:
	ldi arg, 1<<3
	ret
	
show_segment:
	push arg
	push tmp
	clr tmp
seg_tens:
	cpi arg, 10
	brlo seg_end_tens
	inc tmp
	subi arg, 10
	rjmp seg_tens

seg_end_tens:
	push arg
	mov arg, tmp
	rcall segment_digit
	rcall usart_send
	pop arg
	rcall segment_digit
	rcall usart_send
	pop tmp
	pop arg
	ret

init_lcd:
	rcall delay_some_ms ; wait for display to be ready
	rcall delay_some_ms
	rcall delay_some_ms

	clr tmp				; set display as output
	out LCD, tmp
	ser tmp
	out LCD_DD, tmp
	
	rcall init_4bitmode
	ldi arg, 0x2C
	rcall send_ins
	ldi arg, 0x0C
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
	pop arg
	ret
	
show_char:
	push arg
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
	pop arg
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

show_ascii:
	push arg
	push tmp
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
	pop tmp
	pop arg
	ret
	
create_character:
	push arg
	ldi arg, 0x40
	rcall send_ins
	ldi arg, 0x0
	rcall show_char
	ldi arg, 0x4
	rcall show_char
	ldi arg, 0xe
	rcall show_char
	rcall show_char
	rcall show_char
	ldi arg, 0x1f
	rcall show_char
	ldi arg, 0x4
	rcall show_char
	ldi arg, 0x0
	rcall show_char
	ldi arg, 0x80
	rcall send_ins
	pop arg
	ret
