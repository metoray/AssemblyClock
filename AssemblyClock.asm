 .include "m32def.inc"
 .equ FREQ = 11059200 ; frequency in hertz
 .equ USART_BAUDRATE=19200 ; Baud rate for serial communication
 .equ BAUD_PRESCALE=(((FREQ / (USART_BAUDRATE * 16))) - 1) ;  prescaler based on freq

 ; values for the flags register
 .equ counter_flag = 0 					; 
 .equ blink_flag = 1 					; 
 .equ update_display_flag = 2 			; 
 .equ button_flag = 3 					; enabled when buttons should be checked
 .equ button0_flag = 4 					; enabled if button 0 was pressed
 .equ button1_flag = 5 					; enabled if button 1 was pressed
 .equ any_flag = 7 						; enabled when interrupt happens
 
; values for the settings register
.equ settings_on = 0					; are we currently setting the time?
.equ settings_hours = 1					; setting the hours
.equ settings_minutes = 2				; setting the minutes
.equ settings_seconds = 3				; setting the seconds
.equ settings_alarm_hours = 4			; setting the alarm hours
.equ settings_alarm_minutes = 5			; setting the alarm minutes
.equ settings_alarm_status = 6			; setting alarm on/off
.equ settings_done = 7					; setting is done

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
 .def tmp = r16							; we all need more temporary registers...
 .def counter = r17						; counter
 .def int_flags = r18 					; global status flags
 .def arg=r19							; argument register for calling subroutines
 .def counter1=r20						; counter
 .def counter2=r21						; counter
 .def last_counter=r22					; damnit, even more counters
 .def alarm=r23							; alarm status register
 .def buttons=r24						; button counters
 .def blink=r25							; blink status register
 .def settings=r26						; settings status register

;Time in RAM
 .dseg
 time: .byte 4
 alarm_time: .byte 3

 .cseg

;Code start at reset vector 0x00
 .org 0x0
 rjmp main

;Timer 1 Interrupt
 .org OC1Aaddr
 rjmp timer1

time_const: .db high(time), low(time), 3, 60, 60, 24
alarm_const: .db high(alarm_time), low(alarm_time), 2, 60, 24

 main:
	ldi tmp, low(RAMEND)			; reset stack pointer
	out SPL, tmp
	ldi tmp, high(RAMEND)
	out SPH, tmp

	ldi tmp, (1<<CTC1) | (1<<CS12) | (1<<CS10) | (1<<WGM12)	; enable timer with prescaler 1024
	out TCCR1B, tmp

	rcall init_lcd					; init lcd
	
	clr tmp
	out DDRA, tmp
	ser tmp
	out DDRB, tmp					;debug leds

	ldi tmp, high((freq/1024)/16)   ;Set timer compare to 250ms freq/prescaler/16
	out OCR1AH, tmp
	ldi tmp, low((freq/1024)/16)
	out OCR1AL, tmp
	ldi tmp, 1<<OCIE1A				; enable timer compare interrupt
	out TIMSK, tmp
	clr tmp							; clear timer counter
	out TCNT1H, tmp
	out TCNT1L, tmp
	
	rcall init_usart		; init serial communication
	
	clr counter				; clear counter
	
	ldi ZH, high(time)		;point Z reg to time in RAM
	ldi ZL, low(time)
	ldi tmp, 55
	st Z+, tmp				;seconds
	ldi tmp, 59
	st Z+, tmp				;minutes
	ldi tmp, 4
	st Z+, tmp				;hours
	
	ldi ZH, high(alarm_time)
	ldi ZL, low(alarm_time)
	clr tmp
	st Z+, tmp ;hours
	st Z+, tmp ;minutes
	st Z+, tmp ;seconds
	
	ldi blink, 0x0 				;set blink register to none
	rcall create_character 		; create alarm icon on LCD
	sei 						; enable interrupt register
	rcall alarm_clock_start 	; start the clock
	clr settings
	clr buttons
	rjmp loop					; jump to Main Loop

	

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;   Start routines   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	alarm_clock_start:
	ldi blink, (1<<BLINK_HOURS)|(1<<BLINK_MINUTES)|(1<<BLINK_SECONDS)
	ldi alarm, 1<<ALARM_SHOW
	ldi ZH, high(time_const<<1)
	ldi ZL, low(time_const<<1)
	ret


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;      Main Loop     ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
loop:
	sbrs int_flags, any_flag
	rjmp loop							; jumps back to loop if no flags are set
	cbr int_flags, 1<<any_flag			; clear any_flag
	
	sbrs int_flags, counter_flag	
	rjmp loop_blink						; skipped if counter flag is set

	
	sbrs settings, settings_on			; skip update time if we are setting time
	rcall update_time					; update time
	
	cbr int_flags, 1<<counter_flag		; clear counter_flag



loop_blink:
	sbrs int_flags, blink_flag		
	rjmp loop_check_buttons				; jumps to check buttons if blink is turned off
										; invert blink flags, turn off and on
	mov tmp, blink						; copy blink
	swap tmp							; swap nibbles
	andi tmp, 0xF0						; keep blink conditional
	eor blink, tmp						; turn on or off what has to blink
	com tmp								; invert blink
	andi tmp, 0xF0						; remove lower bits
	or blink, tmp						; update blink register with updated status
	sbr int_flags,1<<update_display_flag; set update display flag
	
	cbr int_flags, 1<<blink_flag		; turn off blink flag
	


loop_check_buttons:
	sbrs int_flags, button_flag			
	rjmp loop_test_buttons				; jump to loop_test_buttons if check buttons is turned off
	
	in arg, PINA						; read pinA
	clr tmp								; clear tmp
	
	push buttons						; save button register
	andi buttons, 0xF					; keep lower bits
	inc buttons							; increase buttons
	sbrc buttons, 3						; check if buttons is 8
	ldi buttons, 2						; if so, load 2
	sbrc arg, 0							; check if pinA0 is low(button pressed)
	clr buttons							; if not: reset to 0
	or tmp, buttons						; save lower counter in tmp
	swap tmp	
	cpi buttons, 2						; compare buttons with two
	brne next_button					; if not equal go to next_button
	sbr int_flags, 1<<button0_flag		; else set button0_flag
		
next_button:
	pop buttons							; restore button register
	swap buttons						; swap nibbles
	andi buttons, 0xF					; keep higher bits
	inc buttons							; increase higher counter
	sbrc buttons, 3						; check if higher counter is 8
	ldi buttons, 2						; if so, load 2
	sbrc arg, 1							; check if pinA1 is low(button pressed)
	clr buttons							; is not, reset to 0
	or tmp, buttons						; combine higher and lower counters
	swap tmp							; restore higher/lower counter order
	cpi buttons, 2						; check if higher counter is equal to 2
	brne end_button						; if not, end
	sbr int_flags, 1<<button1_flag		; else set button1_flag
	
end_button:								
	mov buttons, tmp					; move tmp back to buttons, restoring
	
	mov arg, int_flags					; store int_flags
	com arg								; invert flags
	out PORTB, arg						; push to output
	
	cbr int_flags, 1<<button_flag		; clear check_button flag



loop_test_buttons:
	sbrs int_flags, button0_flag
	rjmp loop_test_buttons1				; check if button 0 was pressed, if not, jump to button 1
	
	sbrc settings, settings_on
	rjmp loop_test_buttons1				; check if we are in settings, if so, jump to next button
	ldi tmp, (1<<ALARM_SHOW)|(1<<ALARM_ENABLED)
	eor alarm, tmp
	sbr int_flags, 1<<update_display_flag

	cbr int_flags, 1<<button0_flag
	
loop_test_buttons1:
	sbrs int_flags, button1_flag
	rjmp loop_update_display			; check if button 1 was pressed, if not jump to loop_update_display
	
	sbrc settings, settings_on			; check if we are in settings
	rjmp loop_settings					; if so, jump to settings
	sbr settings, 1<<settings_on		; if we are not in settings set register flag for settings
	sbr settings, 1<<settings_hours

	cbr int_flags, 1<<button1_flag



loop_settings:
	sbrs settings, settings_on
	rjmp loop_update_display			; check if we are in settings, if not, jump to update display
	
	sbrs int_flags, button1_flag		; check if button 1 is pressed
	rjmp loop_settings_button0			; if not, jump to button0
	
	cbr int_flags, 1<<button1_flag		; if so, clear button flag
	cbr settings, 1<<settings_on		; remove settings label
	lsl settings						; move settings one position
	sbrc settings, settings_done	
	rjmp loop_settings_done				; if settings_done is set we are done so jump to there
	sbr settings, 1<<settings_on		; else we are still in settings
	rjmp loop_settings_update

loop_settings_button0:
	sbrs int_flags, button0_flag		; check if button 0 is pressed
	rjmp loop_settings_update			; if not, jump to update_display
	sbrc settings, settings_hours
	ldi arg, 0
	sbrc settings, settings_minutes
	ldi arg, 1
	sbrc settings, settings_seconds
	ldi arg, 2
	sbrc settings, settings_alarm_hours
	ldi arg, 0
	sbrc settings, settings_alarm_minutes
	ldi arg, 1
	rcall increment_segment
	;sbrc settings, settings_alarm_status

	cbr int_flags, 1<<button0_flag
	rjmp loop_settings_update

loop_settings_done:
	rcall settings_update_done
	clr settings
	rjmp loop_update_display

loop_settings_update:					;check in what state we are and update display/blink variables
	sbrc settings, settings_hours
	rcall settings_update_hours
	sbrc settings, settings_minutes
	rcall settings_update_minutes
	sbrc settings, settings_seconds
	rcall settings_update_seconds
	sbrc settings, settings_alarm_hours
	rcall settings_update_alarm_hours
	sbrc settings, settings_alarm_minutes
	rcall settings_update_alarm_minutes
	sbrc settings, settings_alarm_status
	rcall settings_update_alarm_status



loop_update_display:
	sbrs int_flags, update_display_flag	  
	rjmp loop							; jump back to loop if display update is turned off
	
	rcall display_time
	
	cbr int_flags, 1<<update_display_flag
	
	rjmp loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;   Settings helper  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

settings_update_hours:
	ldi blink, (1<<BLINK_HOURS)
	cbr alarm, 1<<ALARM_SHOW
	ret

settings_update_minutes:
	ldi blink, (1<<BLINK_MINUTES)
	ret

settings_update_seconds:
	ldi blink, (1<<BLINK_SECONDS)
	ret
settings_update_alarm_hours:
	ldi arg, 1
	rcall send_ins
	ldi ZH, high(alarm_const<<1)
	ldi ZL, low(alarm_const<<1)
	ldi blink, (1<<BLINK_HOURS)
	sbr alarm, 1<<ALARM_SHOW
	ret

settings_update_alarm_minutes:
	ldi blink, (1<<BLINK_MINUTES)
	ret

settings_update_alarm_status:
	ldi blink, (1<<BLINK_MINUTES)|(1<<BLINK_HOURS)
	ret

settings_update_done:
	clr blink
	sbr alarm, 1<<ALARM_SHOW
	ldi ZH, high(time_const<<1)
	ldi ZL, low(time_const<<1)
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;   Timer Interrupt  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
timer1:
	inc counter
	com counter
	and last_counter, counter
	com counter
	sbr int_flags, 1<<button_flag ; set the button
	sbrc last_counter, 2
	sbr int_flags, 1<<blink_flag ; set the blink on counter = 0b?????0??
	sbrc last_counter, 3
	sbr int_flags, 1<<counter_flag ; set the counter flag on counter = 0b????0???
	mov last_counter, counter
	sbr int_flags, 1<<any_flag			; set the any flag
	reti



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;     Update Time    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

update_time: ; update current time with one second increase
	push ZH								; store Z registers 
	push ZL
	lpm YH, Z+
	lpm YL, Z+
	lpm tmp, Z+
update_time_loop:
	rcall update_number					; update time unit
	brcc update_time_end
	dec tmp
	tst tmp
	brne update_time_loop
update_time_end:
	sbr int_flags, 1<<update_display_flag ;set update display flag since time is updated(inceased one second)
	pop ZL								; return Z registers
	pop ZH
	ret


update_number: 							; time update helper function
	push tmp
	push arg
	ld tmp, Y							; load current value
	lpm arg, Z+							; load max value
	inc tmp								; increment current value
	cp tmp, arg							; compare new value to max value
	brne update_number_no_carry			; if not equal, return without carry
	clr tmp								; else: reset value
	sec									; set carry
	st Y+, tmp							; store new value
	pop arg
	pop tmp
	ret
update_number_no_carry:
	clc									; clear carry
	st Y+, tmp							; store new value
	pop arg
	pop tmp
	ret 

increment_segment:
	push ZL
	push ZH
	push arg
	lpm YH, Z+
	lpm YL, Z+
	lpm tmp, Z+
	sub tmp, arg
	dec tmp
	
	clr arg
	add ZL, tmp
	adc ZH, arg
	add YL, tmp
	adc YH, arg
	
	ld tmp, Y
	lpm arg, Z
	
	inc tmp
	cp tmp, arg
	brne increment_segment_no_overflow
	clr tmp
increment_segment_no_overflow:
	st Y, tmp
	sbr int_flags, 1<<update_display_flag
	pop arg
	pop ZH
	pop ZL
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;    Display Time    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


display_time:
	push ZL
	push ZH	
	lpm YH, Z+
	lpm YL, Z+
	lpm tmp, Z+							; load amount of time segments
	clr arg
	add YL, tmp
	adc YH, arg
	rcall delay_some_ms					; delay a bit
	push blink							; push blink status register
	push tmp							; push amount of time segments
	ldi arg, 0x80						
	rcall send_ins						; LCD: set DDRAM address at 0x00
	rcall usart_send					; MULTI: clear sent bytes
display_time_loop:
	dec tmp								; lower amount of segments
	ld arg, -Y							; load time segments
	lsl blink							; shift blink register, will overflow to carry if needed
	brcs display_time_loop_show         ; if carry set branch to display_time_loop_show 
	;show blank segment
	ldi arg, ' '						; if carry set a blank space should be displayed
	rcall show_char						; LCD send blank char
	rcall show_char
	ldi arg, 0x0
	rcall usart_send					; MULTI: send empty segment
	rcall usart_send
	rjmp display_time_loop_continue		
display_time_loop_show:
	;show segment						; if carry not set a character should be displayed
	rcall show_ascii					; LCD: display timesegment
	rcall show_segment					; MULTI: display timesegment
display_time_loop_continue:
	tst tmp								; test if tmp is zero
	breq display_time_loop_end			; if zero go to end
	ldi arg, ':'						; else: display colon
	rcall show_char						; LCD:  send colon
	rjmp display_time_loop				; jump back to load next segment
display_time_loop_end:
	pop arg								; pop amount of time segments
	ldi tmp, 3							; 
	sub tmp, arg						; subtract 3 from arg
display_time_send_padding:
	tst tmp								; is less than three segments are displayed padding should be added
	breq display_time_last_byte			; if zero then three segments are displayed, jump last byte
	dec tmp								; lower tmp to determine amount of padding
	ldi arg, 0x0						; load blank segment
	rcall usart_send					; send empty segment
	rcall usart_send
	rjmp display_time_send_padding		; jump back to padding
display_time_last_byte:
	pop blink							; pop blink register
	ldi arg, 0b0110						; MULTI: load last byte
	sbrc alarm, ALARM_TRIGGERED			; set alarm bit in last byte if alarm was triggered
	sbr arg, 1<<3
	push arg							; MULTI: push last byte
	ldi arg, 0x88						; LCD: set cursor on alarm position
	rcall send_ins
	ldi arg, ' '						; LCD: push empty char
	rcall show_char
	pop arg								; MULTI: pop last byte
	sbrs blink, ALARM_VISIBLE			; check if alarm is visible
	rjmp display_time_no_alarm			; if bit set jump to no_alarm
	sbrs alarm, ALARM_SHOW				; check if alarm is set
	rjmp display_time_no_alarm			; if bit is set jump to no_alarm
	sbr arg, 0b0001						; MULTI set alarmbit
	push arg							; MULTI: save alarmbit
	ldi arg, 0x88						; LCD: set cursor on alarm position
	rcall send_ins						
	ldi arg, 0x0						; LCD: load alarm icon
	rcall show_char						
	pop arg								; MULTI: pop last byte
display_time_no_alarm:
	rcall usart_send					; MULTI: send last byte to multisegment display
	pop ZH
	pop ZL								
	ret





;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;   Multisegment Routines   ;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; numbertable for conversion of binary to multisegment numbers
numbertable: .db 0b1110111, 0b0100100, 0b1011101, 0b1101101, 0b0101110, 0b1101011, 0b1111011, 0b0100101, 0b1111111, 0b1101111

segment_digit:
	push ZL								; save Z registers
	push ZH								;
	cpi arg, 10							; compare number with 10
	brge segment_error					; greater than 10 is not possible, error
	ldi ZH, high(numbertable*2)			; load numbertable address in Z
	ldi ZL, low(numbertable*2)
	add ZL, arg							; add corresponding number to ZL
	clr arg								; empty arg
	adc ZH, arg							; add possible carry to ZH
	lpm arg, Z							; load corresponding multisegment number
	pop ZH								; restore Z registers
	pop ZL								;
	ret
segment_error:
	ldi arg, 1<<3						; load error register
	ret
	
show_segment:
	push arg							; store timesegment
	push tmp							; store tmp
	clr tmp								; empty tmp
seg_tens:								; TODO: BAD: twice tenssegmenting (see twice tenssegmenting)
	cpi arg, 10							; compare timesegment with 10
	brlo seg_end_tens					; if lower branch
	inc tmp								; else: increase tens
	subi arg, 10						; subtract ten
	rjmp seg_tens						; jump back to seg_tens

seg_end_tens:
	push arg							; store ones
	mov arg, tmp						; load tens in arg
	rcall segment_digit					; prepare multisegment digit
	rcall usart_send					; send multisegment digit
	pop arg								; load ones in arg
	rcall segment_digit					; prepare multisegment digit					
	rcall usart_send					; send multisegment digit
	pop tmp								; restore temp
	pop arg								; restore timesegment
	ret




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;    LCD routines   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

send_ins:
	push arg							; store instruction
	push arg							; once more
	andi arg, 0xF0						; AND first four bits for four bit mode
	out LCD, arg						; send first four bits
	rcall clock_in						; set output enabled
	pop arg								; load instruction
	swap arg							; swap nibbles
	andi arg, 0xF0						; AND last four bits 
	out LCD, arg						; send last four bits
	rcall clock_in						; set output enabled
	rcall delay_some_ms					; wait for display to get ready
	pop arg								; restore instruction
	ret
	
show_char:
	push arg							; store character
	push arg							; once more
	andi arg, 0xf0   					; AND first four bits for four bit mode
	sbr arg, (1 << RS)					; set register select to indicate data transfer
	out LCD, arg						; send first four bits
	rcall clock_in						; set output enabled
	pop arg								; load instruction
	swap arg							; swap nibbles
	andi arg, 0xf0						; AND last four bits 
	sbr arg, (1 << RS)					; set register select to indicate data transfer
	out LCD, arg						; send last four bits
	rcall clock_in						; set output enabled
	pop arg								; restore instruction
	ret

clock_in:
	cbi LCD, ENABLE						; clear enable bit, disable transfer
	sbi LCD, ENABLE						; set enable bit, enable transfer
	rcall delay_one_ish_ms				; some delay to finish transfer
	cbi LCD, ENABLE						; clear enable bit, disable transfer
	ret

show_ascii:
	push arg							; save timesegment
	push tmp							; save tmp
	clr tmp
tens:									; TODO: BAD: twice tenssegmenting (see twice tenssegmenting)
	cpi arg, 10
	brlo end_tens
	inc tmp
	subi arg, 10
	rjmp tens

end_tens:
	subi tmp, -48						; add 48 to tens to create ascii char
	push arg							; save ones
	mov arg, tmp						; move tens to arg
	rcall show_char						; display tens
	pop arg								; restore ones
	subi arg, -48						; add 48 to ones to create ascii char
	rcall show_char						; display ones
	pop tmp								; restore tmp
	pop arg								; restore timesegment
	ret



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;   USART routines   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

init_usart:
	ldi tmp, (1 << RXEN) | (1 << TXEN) 	; set send and receive bit
	out UCSRB, tmp

	ldi tmp, (1 << URSEL) | (1 << UCSZ0) | (1 << UCSZ1)
	out UCSRC, tmp						; set frame format

	ldi tmp, high(BAUD_PRESCALE)		; set baud rate
	out UBRRH, tmp					
	ldi tmp, low(BAUD_PRESCALE)
	out UBRRL, tmp
	ret
	
usart_recv:								; check if receive bit is set
	sbis UCSRA, RXC
	rjmp usart_recv						; if not jump back
	in arg, UDR							; read data
	ret								
	
usart_send:
	sbis UCSRA, UDRE					; check if data register is empty
	rjmp usart_send						; if not wait till empty
	out UDR, arg						; fill data register
	ret





;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;      Init LCD     ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

init_lcd:
	rcall delay_some_ms 				; wait for display to be ready
	rcall delay_some_ms
	rcall delay_some_ms

	clr tmp								; set display as output
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

create_character: 						; create alarm icon on LCD
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




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;   delay routines  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


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
