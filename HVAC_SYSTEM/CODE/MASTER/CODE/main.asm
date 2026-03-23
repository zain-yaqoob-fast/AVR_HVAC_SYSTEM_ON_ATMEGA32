; ======================================================================
; ATmega32 RS485 MASTER + LCD + KEYPAD
; Frequency: 8 MHz
;
; --- FUNCTION ---
; 1. Waits for Packet: [0xAA] -> [Temp] -> [Humid]
; 2. Update LEDs (Always Active):
;    - Temp < 0x82: PC4 ON (Cold)
;    - Temp >= 0x84: PC5 ON (Hot)
;    - Humid < 96: PC6 ON (Low Humid/Intake)
;    - Humid > 0x67: PC7 ON (High Humid/Exhaust)
;
; 3. LCD Logic (Toggled by Keypad '1'):
;    [Mode 0: Temp]
;    - Cold LED ON -> Print "HOT"
;    - Hot LED ON  -> Print "COLD"
;    [Mode 1: Fan - NEW]
;    - PC6 ON -> Print "INTAKE"
;    - PC7 ON -> Print "EXHAUST"
;
; --- HARDWARE CONNECTIONS ---
; [RS485]
; PD0: RXD, PD1: TXD, PD2: DE/RE
;
; [Indicators - PORTC]
; PC4: Cold, PC5: Hot, PC6: Low Humid, PC7: High Humid
;
; [LCD 16x2]
; PORTB: Data, PC0: RS, PC1: RW, PC2: E
;
; [Keypad 4x4 - PORTA - NEW]
; Rows: PA0-PA3 (Output)
; Cols: PA4-PA7 (Input with Pull-up)
; Key '1' assumed at Row 0 (PA0) Col 0 (PA4) intersection
; ======================================================================

.include "m32def.inc"

; --- Registers ---
.def r_temp     = r16
.def r_rxdata   = r17
.def r_state    = r18   ; 0-2=Temp States, 3-5=Fan States
.def r_temp_val = r19
.def r_humid_val= r20
.def r_wait1    = r21
.def r_wait2    = r22
.def r_mode     = r23   ; 0=Temp Mode, 1=Fan Mode
.def r_key_lock = r24   ; Debounce/Lock flag

.cseg
.org 0x0000
    rjmp RESET

RESET:
    ldi r_temp, low(RAMEND)
    out SPL, r_temp
    ldi r_temp, high(RAMEND)
    out SPH, r_temp

    ; --- PORT A Setup (Keypad) ---
    ; PA0-PA3 Output (Rows)
    ; PA4-PA7 Input (Cols)
    ldi r_temp, 0x0F
    out DDRA, r_temp
    ; Enable Pull-ups on Inputs (PA4-PA7) and set Rows High initially
    ldi r_temp, 0xF0
    out PORTA, r_temp

    ; --- PORT B Setup (LCD Data) ---
    ldi r_temp, 0xFF
    out DDRB, r_temp

    ; --- PORT C Setup (LCD Ctrl + LEDs) ---
    sbi DDRC, 0
    sbi DDRC, 1
    sbi DDRC, 2
    sbi DDRC, 4
    sbi DDRC, 5
    sbi DDRC, 6
    sbi DDRC, 7
    
    ; Clear all PORTC output
    cbi PORTC, 0
    cbi PORTC, 1
    cbi PORTC, 2
    cbi PORTC, 4
    cbi PORTC, 5
    cbi PORTC, 6
    cbi PORTC, 7

    ; --- RS485 Setup ---
    sbi DDRD, 2         ; PD2 Output
    cbi PORTD, 2        ; Set Low (Receive Mode)

    ; --- UART Init (9600 Baud) ---
    ldi r_temp, 51
    out UBRRL, r_temp
    clr r_temp
    out UBRRH, r_temp
    ldi r_temp, (1<<RXEN) ; RX Only
    out UCSRB, r_temp
    ldi r_temp, (1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0)
    out UCSRC, r_temp

    ; --- LCD Initialization ---
    rcall DELAY_MS
    ldi r_temp, 0x38
    rcall LCD_CMD
    ldi r_temp, 0x0C
    rcall LCD_CMD
    ldi r_temp, 0x06
    rcall LCD_CMD
    ldi r_temp, 0x01
    rcall LCD_CMD
    rcall DELAY_MS

    ldi r_state, 0
    ldi r_mode, 0       ; Start in Temp Mode
    ldi r_key_lock, 0

; ======================================================================
; MAIN LOOP
; ======================================================================
MAIN_LOOP:
    ; 1. SYNC: Wait for Header (0xAA)
    sbis UCSRA, RXC
    rjmp MAIN_LOOP
    in r_rxdata, UDR
    cpi r_rxdata, 0xAA
    brne MAIN_LOOP

    ; 2. READ TEMP
WAIT_TEMP:
    sbis UCSRA, RXC
    rjmp WAIT_TEMP
    in r_temp_val, UDR

    ; 3. READ HUMIDITY
WAIT_HUMID:
    sbis UCSRA, RXC
    rjmp WAIT_HUMID
    in r_humid_val, UDR

    ; ------------------------------------------------
    ; KEYPAD SCAN (Check Key '1')
    ; ------------------------------------------------
    ; Set Row 0 (PA0) Low, others High
    ldi r_temp, 0xFE ; 1111 1110
    out PORTA, r_temp
    nop
    nop
    ; Read Columns (PIN A)
    in r_temp, PINA
    ; Check Col 0 (PA4 - Bit 4). If 0, Key Pressed.
    sbrc r_temp, 4
    rjmp KEY_NOT_PRESSED

KEY_PRESSED:
    ; Key '1' is down. Check lock to prevent rapid toggle.
    cpi r_key_lock, 1
    breq UPDATE_LEDS    ; Already handled this press
    
    ; Toggle Mode (0->1, 1->0)
    ldi r_key_lock, 1   ; Lock it
    ldi r_temp, 1
    eor r_mode, r_temp  ; XOR with 1 toggles bit 0
    
    ; Force State Reset to refresh LCD immediately
    ldi r_state, 0xFF   
    rcall LCD_CLEAR
    rjmp UPDATE_LEDS

KEY_NOT_PRESSED:
    ldi r_key_lock, 0   ; Release lock

    ; ------------------------------------------------
    ; UPDATE LEDS (Always run background logic)
    ; ------------------------------------------------
UPDATE_LEDS:
    ; --- Humid LEDs ---
    cbi PORTC, 6
    cbi PORTC, 7
    cpi r_humid_val, 96
    brlo SET_HUMID_LOW
    cpi r_humid_val, 0x67
    brsh SET_HUMID_HIGH
    rjmp UPDATE_TEMP_LEDS

SET_HUMID_LOW:
    sbi PORTC, 6
    rjmp UPDATE_TEMP_LEDS
SET_HUMID_HIGH:
    sbi PORTC, 7

UPDATE_TEMP_LEDS:
    ; --- Temp LEDs ---
    cbi PORTC, 4
    cbi PORTC, 5
    cpi r_temp_val, 0x82
    brlo SET_TEMP_COLD
    cpi r_temp_val, 0x84
    brsh SET_TEMP_HOT
    rjmp CHECK_LCD_MODE

SET_TEMP_COLD:
    sbi PORTC, 4
    rjmp CHECK_LCD_MODE
SET_TEMP_HOT:
    sbi PORTC, 5

    ; ------------------------------------------------
    ; LCD LOGIC (Dependent on Mode)
    ; ------------------------------------------------
CHECK_LCD_MODE:
    cpi r_mode, 1
    breq LCD_FAN_MODE

LCD_TEMP_MODE:
    ; (Existing Logic: Cold LED -> HOT msg)
    sbic PORTC, 4       ; If Cold LED (PC4) is ON
    rjmp STATE_COLD_MSG
    sbic PORTC, 5       ; If Hot LED (PC5) is ON
    rjmp STATE_HOT_MSG
    rjmp STATE_NORMAL   ; Else Normal

LCD_FAN_MODE:
    ; (New Logic: PC6 -> INTAKE, PC7 -> EXHAUST)
    sbic PORTC, 6       ; If Low Humid (PC6) is ON
    rjmp STATE_INTAKE_MSG
    sbic PORTC, 7       ; If High Humid (PC7) is ON
    rjmp STATE_EXHAUST_MSG
    rjmp STATE_NORMAL

    ; --- LCD STATES ---
    ; FIXED: Replaced 'breq MAIN_LOOP' with 'brne ... rjmp MAIN_LOOP'
    ; to fix "Branch out of range" errors.

STATE_NORMAL:
    cpi r_state, 0
    brne DO_NORMAL_UPDATE
    rjmp MAIN_LOOP      ; Already normal, loop back
DO_NORMAL_UPDATE:
    ldi r_state, 0
    rcall LCD_CLEAR
    rjmp MAIN_LOOP

STATE_COLD_MSG:
    cpi r_state, 1
    brne DO_COLD_UPDATE
    rjmp MAIN_LOOP
DO_COLD_UPDATE:
    ldi r_state, 1
    rcall SHOW_HOT_MSG  ; Reversed
    rjmp MAIN_LOOP

STATE_HOT_MSG:
    cpi r_state, 2
    brne DO_HOT_UPDATE
    rjmp MAIN_LOOP
DO_HOT_UPDATE:
    ldi r_state, 2
    rcall SHOW_COLD_MSG ; Reversed
    rjmp MAIN_LOOP

STATE_INTAKE_MSG:
    cpi r_state, 3
    brne DO_INTAKE_UPDATE
    rjmp MAIN_LOOP
DO_INTAKE_UPDATE:
    ldi r_state, 3
    rcall SHOW_INTAKE
    rjmp MAIN_LOOP

STATE_EXHAUST_MSG:
    cpi r_state, 4
    brne DO_EXHAUST_UPDATE
    rjmp MAIN_LOOP
DO_EXHAUST_UPDATE:
    ldi r_state, 4
    rcall SHOW_EXHAUST
    rjmp MAIN_LOOP

; ======================================================================
; SUBROUTINES
; ======================================================================

SHOW_COLD_MSG:
    rcall LCD_CLEAR
    ldi r_temp, 'C'
    rcall LCD_CHAR
    ldi r_temp, 'O'
    rcall LCD_CHAR
    ldi r_temp, 'L'
    rcall LCD_CHAR
    ldi r_temp, 'D'
    rcall LCD_CHAR
    ret

SHOW_HOT_MSG:
    rcall LCD_CLEAR
    ldi r_temp, 'H'
    rcall LCD_CHAR
    ldi r_temp, 'O'
    rcall LCD_CHAR
    ldi r_temp, 'T'
    rcall LCD_CHAR
    ret

SHOW_INTAKE:
    rcall LCD_CLEAR
    ldi r_temp, 'I'
    rcall LCD_CHAR
    ldi r_temp, 'N'
    rcall LCD_CHAR
    ldi r_temp, 'T'
    rcall LCD_CHAR
    ldi r_temp, 'A'
    rcall LCD_CHAR
    ldi r_temp, 'K'
    rcall LCD_CHAR
    ldi r_temp, 'E'
    rcall LCD_CHAR
    ret

SHOW_EXHAUST:
    rcall LCD_CLEAR
    ldi r_temp, 'E'
    rcall LCD_CHAR
    ldi r_temp, 'X'
    rcall LCD_CHAR
    ldi r_temp, 'H'
    rcall LCD_CHAR
    ldi r_temp, 'A'
    rcall LCD_CHAR
    ldi r_temp, 'U'
    rcall LCD_CHAR
    ldi r_temp, 'S'
    rcall LCD_CHAR
    ldi r_temp, 'T'
    rcall LCD_CHAR
    ret

LCD_CLEAR:
    ldi r_temp, 0x01
    rcall LCD_CMD
    rcall DELAY_MS
    ret

LCD_CMD:
    out PORTB, r_temp
    cbi PORTC, 0
    cbi PORTC, 1
    sbi PORTC, 2
    nop
    nop
    cbi PORTC, 2
    rcall DELAY_FAST
    ret

LCD_CHAR:
    out PORTB, r_temp
    sbi PORTC, 0
    cbi PORTC, 1
    sbi PORTC, 2
    nop
    nop
    cbi PORTC, 2
    rcall DELAY_FAST
    ret

DELAY_MS:
    ldi r_wait1, 255
    ldi r_wait2, 20
DL_1:
    dec r_wait1
    brne DL_1
    dec r_wait2
    brne DL_1
    ret

DELAY_FAST:
    ldi r_wait1, 255
DL_2:
    dec r_wait1
    brne DL_2
    ret