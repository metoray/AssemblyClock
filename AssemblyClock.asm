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
 .equ clear_display_flag = 6
 .equ any_flag = 7 						; enabled when interrupt happens

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

	ldi tmp, (1<<CTC1) | (1<<CS12) | (1<<WGM12)	; enable timer with prescaler 256
	out TCCR1B, tmp

	rcall init_lcd					; init lcd
	
	clr tmp
	out DDRA, tmp
	ser tmp
	out DDRB, tmp					;debug leds

	ldi tmp, high((freq/256)/32)   ;Set timer compare to 250ms freq/prescaler/16
	out OCR1AH, tmp
	ldi tmp, low((freq/256)/32)
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
	ldi tmp, 0
	st Z+, tmp				;seconds
	ldi tmp, 0
	st Z+, tmp				;minutes
	ldi tmp, 0
	st Z+, tmp				;hours
	
	ldi ZH, high(alarm_time)
	ldi ZL, low(alarm_time)
	clr tmp
	st Z+, tmp ;seconds
	st Z+, tmp ;minutes
	st Z+, tmp ;hours
	
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

	
	cpi settings, 0x40					; check if we are in settings, time has to halt
	breq time_is_not_frozen				; not in settings, update time
	cpi settings, 0x0					
	breq time_is_not_frozen				; not in settings, update time
	rjmp time_is_frozen					; in settings, don't update time
	
time_is_not_frozen:
	rcall update_time					; update time
	
	push ZH								; save Z registers
	push ZL
	ldi YH, high(alarm_const<<1)		; load alarmpointer
	ldi YL, low(alarm_const<<1)
	ldi ZH, high(time_const<<1)			; load timepointer
	ldi ZL, low(time_const<<1)
	rcall compare_times					; compare times
	brtc no_buzz						; branch if T flag is cleared
	sbrc alarm, ALARM_ENABLED			; if alarm enabled
	sbr alarm, 1<<ALARM_TRIGGERED		; set the alarm bit
no_buzz:	
	pop ZL
	pop ZH
	
time_is_frozen:
	
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
	rjmp loop_button0				; jump to loop_test_buttons if check buttons is turned off
	
	in arg, PINA						; read pinA
	clr tmp								; clear tmp
	
	push buttons						; save button register
	andi buttons, 0xF					; keep lower bits
	inc buttons							; increase buttons
	sbrc buttons, 4						; check if buttons is 16
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
	sbrc buttons, 4						; check if higher counter is 16
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
	;out PORTB, arg						; push to output
	
	cbr int_flags, 1<<button_flag		; clear check_button flag



loop_button0:
	sbrs int_flags, button0_flag
	rjmp loop_button1				; check if button 0 was pressed, if not, jump to button 1
	
	sbr int_flags, 1<<update_display_flag
	
	cpi settings, 0x30
	breq toggle_alarm
	cpi settings, 0x40
	breq toggle_alarm
	mov arg, settings
	andi arg, 0xF
	rcall increment_segment
	rjmp loop_button0_end
toggle_alarm:
	cbr alarm, 1<<ALARM_TRIGGERED	; disable buzzer
	ldi tmp, 1<<ALARM_ENABLED
	eor alarm, tmp
	
loop_button0_end:
	cbr int_flags, 1<<button0_flag
	
loop_button1:
	sbrs int_flags, button1_flag
	rjmp loop_clear_display			; check if button 1 was pressed, if not jump to loop_update_display
	
	rcall increment_state
	sbr int_flags, 1<<update_display_flag

	cbr int_flags, 1<<button1_flag

loop_clear_display:
	sbrs int_flags, clear_display_flag
	rjmp loop_update_display
	
	ldi arg, 0x1
	rcall send_ins
	
	cbr int_flags, 1<<clear_display_flag

loop_update_display:
	sbrs int_flags, update_display_flag	  
	rjmp loop							; jump back to loop if display update is turned off
	
	rcall display_time
	
	rcall update_alarm_indicator
	cbr int_flags, 1<<update_display_flag
	
	out PORTB, alarm
	
	rjmp loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;   Settings helper  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
settings_update_clock_pointer:
	push settings
	push tmp
	andi settings, 0xF0 ; obtain current state
	swap settings
	cpi settings, 2
	breq settings_update_clock_pointer_alarm
	cpi settings, 3
	breq settings_update_clock_pointer_alarm
	ldi ZH, high(time_const<<1)
	ldi ZL, low(time_const<<1)
	rjmp settings_update_clock_pointer_return
settings_update_clock_pointer_alarm:
	ldi ZH, high(alarm_const<<1)
	ldi ZL, low(alarm_const<<1)
settings_update_clock_pointer_return:
	pop tmp
	pop settings
	push arg
	sbr int_flags, 1<<clear_display_flag
	pop arg
	ret

max_substate: .db 1, 3, 2, 1, 1
increment_state:
	mov tmp, settings
	andi settings, 0xF0
	andi tmp, 0x0F
	swap settings
	
	clr arg
	ldi ZH, high(max_substate<<1)
	ldi ZL, low(max_substate<<1)
	
	add ZL, settings
	adc ZH, arg
	
	lpm arg, Z+
	
	inc tmp
	cp tmp, arg
	brne increment_state_return
	
	inc settings
	clr tmp
	
	cpi settings, 5
	brne increment_state_return
	ldi settings, 1
	
increment_state_return:
	swap settings
	or settings, tmp
	rcall settings_update_clock_pointer
	rcall settings_update_blink
	ret	
	
settings_update_blink:
	push settings
	push arg
	andi blink, 1<<BLINK_ALARM
	mov arg, settings
	andi arg, 0xF0
	swap arg
	andi settings, 0xF
	ldi tmp, 1
	cpi arg, 2
	cpse arg, tmp
	brne settings_update_blink_all_or_nothing 
	ldi tmp, 1<<BLINK_HOURS
	inc settings
settings_update_blink_shift:
	dec settings
	breq settings_update_blink_end
	lsr tmp
	rjmp settings_update_blink_shift
settings_update_blink_end:
	or blink, tmp
	pop arg
	pop settings
	ret
	
settings_update_blink_all_or_nothing:
	mov settings, arg
	clr arg
	ldi tmp, 4
	cpse settings, tmp
	ldi arg, 0b1110
	or blink, arg
	pop arg
	pop settings
	ret
	
update_alarm_indicator:
	sbr blink, 1<<BLINK_ALARM
	mov tmp, settings
	swap tmp
	andi tmp, 0x0F
	cpi tmp, 0x2
	breq update_alarm_indicator_do_blink
	sbrs alarm, 1<<ALARM_TRIGGERED
	cbr blink, 1<<BLINK_ALARM
update_alarm_indicator_do_blink:
	sbr alarm, 1<<ALARM_SHOW
	cpi tmp, 0x2
	breq update_alarm_indicator_show
	sbrs alarm, ALARM_ENABLED
	cbr alarm, 1<<ALARM_SHOW
update_alarm_indicator_show:
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
	sbrc last_counter, 3
	sbr int_flags, 1<<blink_flag ; set the blink on counter = 0b????0???
	sbrc last_counter, 4
	sbr int_flags, 1<<counter_flag ; set the counter flag on counter = 0b???0????
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

increment_segment:						; increment one timesegments
	push ZL								; save Z registers
	push ZH								;
	push arg							; save the argument(time designator)
	lpm YH, Z+							; load timepointer
	lpm YL, Z+							;
	lpm tmp, Z+							; load amount of segments
	sub tmp, arg						; subtract amount of segments to get wanted segments
	dec tmp								; decrease once more
	
	clr arg								; clear arg
	add ZL, tmp							; point to segment
	adc ZH, arg							; 
	add YL, tmp							; point to segment
	adc YH, arg							; 
	
	ld tmp, Y							; load segment
	lpm arg, Z							; load overflow value
	
	inc tmp								; increase segment
	cp tmp, arg							; compare with overflow value
	brne increment_segment_no_overflow  ; branch if not equal
	clr tmp								; if equal reset to zero
increment_segment_no_overflow:
	st Y, tmp							; save segment
	sbr int_flags, 1<<update_display_flag ; set update display flag
	pop arg								; restore arg
	pop ZH								; restore Z registers
	pop ZL								;
	ret
	
compare_times:
	push arg							; save registers
	push tmp							;
	push ZH								;
	push ZL								;
	lpm tmp, Z+ 						; TH1
	push tmp							
	lpm tmp, Z+ 						; TL1					
	push tmp							
	lpm r0, Z							; size of time 1
	rcall swap_pointers
	lpm tmp, Z+ 						; TH2
	push tmp
	lpm tmp, Z+ 						; TL2
	push tmp
	lpm r1, Z							; size of time 2
	
	pop YL								; TL2
	pop YH								; TH2
	pop ZL								; TL1
	pop ZH								; TH1
	cp r0, r1							; compare size1 to size2
	brge compare_times_correct_order	; time1 has more units than time2
	rcall swap_pointers					; swap times
	push r0								; swap sizes
	push r1
	pop r0
	pop r1
compare_times_correct_order:
	mov tmp, r0							; calculate difference in sizes
	sub tmp, r1
compare_times_check_zeroes:
	tst tmp
	breq compare_times_check_common_segments
	dec tmp
	dec r0
	ld arg, Z+
	tst arg
	brne compare_times_return_false
	rjmp compare_times_check_zeroes
compare_times_check_common_segments:
	ld arg, Z+
	ld tmp, Y+
	cp arg, tmp
	brne compare_times_return_false
	dec r0
	brne compare_times_check_common_segments
	pop ZL
	pop ZH
	pop tmp
	pop arg
	set
	ret
	
compare_times_return_false:
	pop ZL								; return Z registers 
	pop ZH
	pop tmp								; return tmp register
	pop arg								; return arg register
	clt									; clear T flag
	ret

swap_pointers:							; Swap the pointers
	push ZL
	push ZH
	push YL
	push YH
	pop ZH
	pop ZL
	pop YH
	pop YL
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;    Display Time    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


display_time:
	mov tmp, blink						; process blink status
	andi tmp, 0xF						; remove higher bits
	swap tmp							; swap nibbles
	com tmp								; invert bits
	cbr tmp, 0xF						; remove lower bits
	or blink, tmp						; combine tmp and blink back togehter
	push ZL								; save Z registers
	push ZH								;
	lpm YH, Z+							; load address in Z to Y 
	lpm YL, Z+							; 
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
	push arg							; save arg
display_time_send_padding:
	tst tmp								; is less than three segments are displayed padding should be added
	breq display_time_last_byte			; if zero then three segments are displayed, jump last byte
	dec tmp								; lower tmp to determine amount of padding
	ldi arg, 0x0						; load blank segment
	rcall usart_send					; send empty segment
	rcall usart_send
	rjmp display_time_send_padding		; jump back to padding
display_time_last_byte:
	pop arg								; restore arg
	mov tmp, arg						; copy arg to tmp
	pop blink							; pop blink register
	ldi arg, 0b0110						; MULTI: load last byte
	cpi tmp, 3							; compare tmp with three
	brge display_time_last_byte_end		; if greater or equal branch 
	cbr arg, 1<<1						; remove one byte for colon
	cpi tmp, 2							; compare with two
	brge display_time_last_byte_end		; branch if greater or equal
	cbr arg, 1<<2						; remove second colon(none remain)
display_time_last_byte_end:
	sbrc alarm, ALARM_TRIGGERED			; set alarm bit in last byte if alarm was triggered
	sbr arg, 1<<3
	push arg							; MULTI: push last byte
	ldi arg, 0x88						; LCD: set cursor on alarm position
	rcall send_ins
	ldi tmp, ' '						; LCD: push empty char
	pop arg								; MULTI: pop last byte
	sbrs blink, ALARM_VISIBLE			; check if alarm is visible
	rjmp display_time_no_alarm			; if bit set jump to no_alarm
	sbrs alarm, ALARM_SHOW				; check if alarm is set
	rjmp display_time_no_alarm			; if bit is set jump to no_alarm
	sbr arg, 0b0001						; MULTI set alarmbit
	push arg							; MULTI: save alarmbit					
	ldi tmp, 0x0						; LCD: load alarm icon					
	pop arg								; MULTI: pop last byte
display_time_no_alarm:
	rcall usart_send					; MULTI: send last byte to multisegment display
	mov arg, tmp
	rcall show_char
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
	ldi ZH, high(numbertable<<1)			; load numbertable address in Z
	ldi ZL, low(numbertable<<1)
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
