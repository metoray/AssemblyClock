 .include "m32def.inc"
 .equ FREQ = 11059200 ; frequency in hertz
 .equ USART_BAUDRATE=19200 ; Baud rate for serial communication
 .equ BAUD_PRESCALE=(((FREQ / (USART_BAUDRATE * 16))) - 1) ;  prescaler based on freq
 
 ; values for the flags register
 .equ counter_flag = 0 ; 
 .equ blink_flag = 1 ; 
 .equ update_display_flag = 2 ; 
 .equ any_flag = 7 ; enabled when interrupt happens
 
 ;Ports
 .equ LCD=PORTD
 .equ LCD_DD=DDRD
 .equ ENABLE=2
 .equ RS=3

 ;Blink flags
 .equ BLINK_ALARM=0						;does it have to blink bits
 .equ BLINK_SECONDS=1
 .equ BLINK_MINUTES=2
 .equ BLINK_HOURS=3
 .equ ALARM_VISIBLE=BLINK_ALARM+4		;if it blinks, is it visible or turned off bits
 .equ SECONDS_VISIBLE=BLINK_SECONDS+4
 .equ MINUTES_VISIBLE=BLINK_MINUTES+4
 .equ HOURS_VISIBLE=BLINK_HOURS+4

 ;Alarm flags
 .equ ALARM_SHOW=0
 .equ ALARM_ENABLED=1
 .equ ALARM_TRIGGERED=2

;Defined registers
 .def tmp = r16
 .def counter = r17
 .def int_flags = r18
 .def arg=r19
 .def counter1=r20
 .def counter2=r21
 .def last_counter=r22
 .def alarm=r23
 .def blink=r25

;Time in RAM
 .dseg
 time: .byte 4

 .cseg

;Code start at reset vector 0x00
 .org 0x0
 rjmp main

;Timer 1 Interrupt
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


	ldi tmp, high((freq/1024)/4)    ;Set timer compare to 250ms freq/prescaler/4
	out OCR1AH, tmp
	ldi tmp, low((freq/1024)/4)
	out OCR1AL, tmp

	ldi tmp, 1<<OCIE1A	; enable timer compare interrupt
	out TIMSK, tmp

	clr tmp				; clear timer counter
	out TCNT1H, tmp
	out TCNT1L, tmp
	
	rcall init_usart	; init serial communication
	
	clr counter			; clear counter
	
	ldi ZH, high(time)	;point Z reg to time in RAM
	ldi ZL, low(time)
	
	ldi tmp, 2  
	st Z+, tmp  ;amount of time segments
	ldi tmp, 4
	st Z+, tmp	;hours
	ldi tmp, 59
	st Z+, tmp	;minutes
	ldi tmp, 55
	st Z+, tmp	;seconds
	
	ldi blink, 0x0 ;set blink register to none
	
	rcall create_character ; create alarm icon on LCD
	
	sei ; enable interrupt register

	rcall alarm_clock_start ; start the clock


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;      Main Loop     ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
loop:
	sbrs int_flags, any_flag
	rjmp loop						; jumps back to loop if no flags are set
	cbr int_flags, 1<<any_flag		; clear any_flag
	
	sbrs int_flags, counter_flag	
	rjmp loop_blink					; skipped if counter flag is set
	
	rcall update_time				; update time
	
	cbr int_flags, 1<<counter_flag	; clear counter_flag


loop_blink:
	sbrs int_flags, blink_flag		
	rjmp loop_update_display		; jumps to display update if blink is turned off
	
	mov tmp, blink					
	swap tmp
	andi tmp, 0xF0
	eor blink, tmp
	com tmp
	andi tmp, 0xF0
	or blink, tmp
	;ser blink
	sbr int_flags, 1<<update_display_flag ; set update display flag
	
	cbr int_flags, 1<<blink_flag		  ; turn off blink flag
	


loop_update_display:
	sbrs int_flags, update_display_flag	  
	rjmp loop							  ; jump back to loop if display update is turned off
	
	ldi ZH, high(time)
	ldi ZL, low(time)
	rcall display_time
	
	cbr int_flags, 1<<update_display_flag
	
	rjmp loop


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;   Timer Interrupt  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
timer1:
	inc counter
	com counter
	and last_counter, counter
	com counter
	sbrc last_counter, 0
	sbr int_flags, 1<<blink_flag 		; set the blink flag on counter = 0x?1 and 0x?3
	sbrc last_counter, 1
	sbr int_flags, 1<<counter_flag		; set the counter flag on counter = 0x?3
	mov last_counter, counter
	sbr int_flags, 1<<any_flag			; set the any flag
	reti


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;     Update Time    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

update_time: ; update current time with one second increase
	push ZH								; store Z registers 
	push ZL
	ldi ZH, high(time+4)				; load Z with adress of time+ 4 bytes
	ldi ZL, low(time+4)
	ldi arg, 60							; load 60 for minutes/seconds comparison
	rcall update_number					; update seconds
	brcc update_time_end				; if carry cleared no minute update needed
	rcall update_number					; update minutes
	brcc update_time_end				; if carry cleared no hour update needed
	ldi arg, 24							; load 24 for hour comparison
	rcall update_number
update_time_end:
	sbr int_flags, 1<<update_display_flag ;set update display flag since time is updated(inceased one second)
	pop ZL								; return Z registers
	pop ZH
	ret


update_number: ; time update helper function
	ld tmp, -Z ; load second/minute/hour
	inc tmp	   ; increase time
	cp tmp, arg; compare time with 60 or 24
	clc		   ; clear the carry
	brne update_number_no_carry ; if time not equal with 60/24 no update needed
	clr tmp ; if time is equal the next time step should be increased and this one cleared
	sec		; set the carry to indicate that next step should be increased
update_number_no_carry:
	st Z, tmp ; store the new time
	ret 



display_time:
	ld tmp, Z+
	rcall delay_some_ms
	push blink
	push tmp
	ldi arg, 0x80
	rcall send_ins
	rcall usart_send
display_time_loop:
	dec tmp
	ld arg, Z+
	lsl blink
	brcs display_time_loop_show
	;show blank segment
	ldi arg, ' '
	rcall show_char
	rcall show_char
	ldi arg, 0x0
	rcall usart_send
	rcall usart_send
	rjmp display_time_loop_continue
display_time_loop_show:
	;show segment
	rcall show_ascii
	rcall show_segment
display_time_loop_continue:
	tst tmp
	breq display_time_loop_end
	ldi arg, ':'
	rcall show_char
	rjmp display_time_loop
display_time_loop_end:
	pop arg
	ldi tmp, 3
	sub tmp, arg
display_time_send_padding:
	tst tmp
	breq display_time_last_byte
	dec tmp
	ldi arg, 0x0
	rcall usart_send
	rcall usart_send
	rjmp display_time_send_padding
display_time_last_byte:
	pop blink
	ldi arg, 0b0110
	push arg
	ldi arg, 0x88
	rcall send_ins
	ldi arg, ' '
	rcall show_char
	pop arg
	sbrs blink, ALARM_VISIBLE
	rjmp display_time_no_alarm
	sbrs alarm, ALARM_SHOW
	rjmp display_time_no_alarm
	sbr arg, 0b0001
	push arg
	ldi arg, 0x88
	rcall send_ins
	ldi arg, 0x0
	rcall show_char
	pop arg
display_time_no_alarm:
	rcall usart_send
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
	
create_character: ; create alarm icon on LCD
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

alarm_clock_start:
	ldi blink, (1<<BLINK_HOURS)|(1<<BLINK_MINUTES)|(1<<BLINK_SECONDS)|(1<<BLINK_ALARM)
	ldi alarm, 1<<ALARM_SHOW
	ret
