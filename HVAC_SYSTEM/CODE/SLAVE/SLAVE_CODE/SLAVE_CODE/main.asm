;
; SLAVE_CODE.asm
;
; Created: 3/23/2026 5:40:30 PM
; Author : Zain Yaqoob
;


; Replace with your application code
start:; ======================================================================
; ATmega32 Combined System: BME280 + MQ135 + RS485 SLAVE
; Frequency: 8 MHz
; ======================================================================

.include "m32def.inc"

; --- Registers ---
.def r_temp     = r16
.def r_loop     = r17
.def r_addr_W   = r18   ; I2C Write Address
.def r_addr_R   = r19   ; I2C Read Address
.def r_adcL     = r20   ; ADC Low Byte
.def r_adcH     = r21   ; ADC High Byte
.def r_dataT    = r22   ; Temp MSB
.def r_dataH    = r23   ; Humidity MSB
.def r_threshL  = r24   ; ADC Threshold Low
.def r_threshH  = r25   ; ADC Threshold High

.cseg
.org 0x0000
    rjmp RESET

RESET:
    ; --- Stack Pointer Init ---
    ldi r_temp, low(RAMEND)
    out SPL, r_temp
    ldi r_temp, high(RAMEND)
    out SPH, r_temp

    ; --- PORT B Setup (Temp Outputs) ---
    sbi DDRB, 0     ; PB0 Output
    sbi DDRB, 1     ; PB1 Output
    cbi PORTB, 0    ; All OFF
    cbi PORTB, 1

    ; --- PORT D Setup (Shared Outputs + RS485) ---
    ; PD7 (Fan), PD3 (Fan), PD2 (RS485 DE/RE) = Output
    ldi r_temp, (1<<7)|(1<<3)|(1<<2)   
    out DDRD, r_temp
    cbi PORTD, 2    ; RS485 Receive Mode by default

    ; --- UART Init (RS485 @ 9600 Baud, 8MHz) ---
    ldi r_temp, 51      ; UBRR for 9600 baud
    out UBRRL, r_temp
    clr r_temp
    out UBRRH, r_temp
    ; Enable TX only (Slave mainly talks here)
    ldi r_temp, (1<<TXEN) 
    out UCSRB, r_temp
    ; 8-bit data, 1 stop bit
    ldi r_temp, (1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0)
    out UCSRC, r_temp

    ; --- ADC Initialization (MQ135) ---
    ldi r_temp, (1<<REFS0)
    out ADMUX, r_temp
    ldi r_temp, (1<<ADEN)|(1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0)
    out ADCSRA, r_temp

    ; --- I2C Init (BME280) ---
    ldi r_temp, 2
    out TWBR, r_temp
    ldi r_temp, 0
    out TWSR, r_temp

    ; --- VISUAL CHECK ---
    sbi PORTB, 0
    sbi PORTD, 7
    rcall DELAY_MS
    cbi PORTB, 0
    cbi PORTD, 7
    
    sbi PORTB, 1
    sbi PORTD, 3
    rcall DELAY_MS
    cbi PORTB, 1
    cbi PORTD, 3

    ; --- BME280 SETUP: Detect Sensor Address ---
    ldi r_addr_W, 0xEC
    ldi r_addr_R, 0xED
    rcall CHECK_CHIP_ID
    cpi r_temp, 0x60
    breq SENSOR_FOUND

    ldi r_addr_W, 0xEE
    ldi r_addr_R, 0xEF
    rcall CHECK_CHIP_ID
    cpi r_temp, 0x60
    breq SENSOR_FOUND

ERROR_LOOP:
    sbi PORTB, 0
    rcall DELAY_FAST
    cbi PORTB, 0
    rcall DELAY_FAST
    rjmp ERROR_LOOP

SENSOR_FOUND:
    ; --- Configure BME280 ---
    rcall TWI_START
    mov r_temp, r_addr_W
    rcall TWI_WRITE
    ldi r_temp, 0xF2    ; ctrl_hum
    rcall TWI_WRITE
    ldi r_temp, 0x01    ; Humidity x1
    rcall TWI_WRITE
    rcall TWI_STOP

    rcall TWI_START
    mov r_temp, r_addr_W
    rcall TWI_WRITE
    ldi r_temp, 0xF4    ; ctrl_meas
    rcall TWI_WRITE
    ldi r_temp, 0x23    ; Temp x1, Normal Mode
    rcall TWI_WRITE
    rcall TWI_STOP

; ======================================================================
; MAIN APPLICATION LOOP
; ======================================================================
MAIN_LOOP:
    ; -------------------------------------------------------
    ; 1. READ DATA
    ; -------------------------------------------------------
    
    ; Read Temp MSB
    rcall TWI_START
    mov r_temp, r_addr_W
    rcall TWI_WRITE
    ldi r_temp, 0xFA
    rcall TWI_WRITE
    rcall TWI_START
    mov r_temp, r_addr_R
    rcall TWI_WRITE
    rcall TWI_READ_NACK
    mov r_dataT, r_temp
    rcall TWI_STOP

    ; Read Humid MSB
    rcall TWI_START
    mov r_temp, r_addr_W
    rcall TWI_WRITE
    ldi r_temp, 0xFD
    rcall TWI_WRITE
    rcall TWI_START
    mov r_temp, r_addr_R
    rcall TWI_WRITE
    rcall TWI_READ_NACK
    mov r_dataH, r_temp
    rcall TWI_STOP

    ; Read ADC (MQ135)
    sbi ADCSRA, ADSC
WAIT_ADC:
    sbis ADCSRA, ADSC
    rjmp WAIT_ADC
    in r_adcL, ADCL
    in r_adcH, ADCH

    ; -------------------------------------------------------
    ; 2. UPDATE LOGIC (Reset -> Humid -> Air Override)
    ; -------------------------------------------------------
    
    cbi PORTD, 7
    cbi PORTD, 3
    
    rcall UPDATE_TEMP_LEDS
    rcall UPDATE_HUMID_LEDS
    rcall UPDATE_AIR_LEDS

    ; --- RS485 TRANSMISSION START ---
    ; Send Packet: [0xAA] -> [Temp] -> [Humid]
    rcall RS485_SEND_PACKET
    ; --- RS485 TRANSMISSION END ---

    rcall DELAY_MS
    rjmp MAIN_LOOP

; ======================================================================
; SUBROUTINES
; ======================================================================

; --- NEW: RS485 Transmit Routine ---
RS485_SEND_PACKET:
    ; 1. Set DE/RE (PD2) High to Enable Transmission
    sbi PORTD, 2
    
    ; 2. Send Header (0xAA)
    sbis UCSRA, UDRE
    rjmp RS485_SEND_PACKET + 2
    ldi r_temp, 0xAA
    out UDR, r_temp

    ; 3. Send Temp
WAIT_TX_1:
    sbis UCSRA, UDRE
    rjmp WAIT_TX_1
    out UDR, r_dataT

    ; 4. Send Humid
WAIT_TX_2:
    sbis UCSRA, UDRE
    rjmp WAIT_TX_2
    out UDR, r_dataH

    ; 5. Wait for Transmission Complete Flag (TXC)
WAIT_TX_COMPLETE:
    sbis UCSRA, TXC
    rjmp WAIT_TX_COMPLETE

    ; 6. Clear TXC flag
    sbi UCSRA, TXC
    
    ; 7. Set DE/RE Low (Return to Receive/Idle mode)
    cbi PORTD, 2
    ret

; --- BME280 Logic ---
UPDATE_TEMP_LEDS:
    cpi r_dataT, 0x82
    brlo T_COLD
    cpi r_dataT, 0x84
    brsh T_HOT
    cbi PORTB, 0
    cbi PORTB, 1
    ret
T_COLD:
    sbi PORTB, 0
    cbi PORTB, 1
    ret
T_HOT:
    cbi PORTB, 0
    sbi PORTB, 1
    ret

UPDATE_HUMID_LEDS:
    cpi r_dataH, 96
    brlo H_LOW      
    cpi r_dataH, 0x67
    brsh H_HIGH     
    ret

H_LOW:
    sbi PORTD, 3   
    ret
H_HIGH:
    sbi PORTD, 7   
    ret

; --- MQ135 Logic ---
UPDATE_AIR_LEDS:
    ldi r_threshL, low(10)
    ldi r_threshH, high(10)
    cp  r_adcL, r_threshL
    cpc r_adcH, r_threshH
    brsh AIR_BAD    
    ret

AIR_BAD:
    sbi PORTD, 7    
    sbi PORTD, 3    
    ret

; --- Drivers & Utilities ---

CHECK_CHIP_ID:
    rcall TWI_START
    mov r_temp, r_addr_W
    rcall TWI_WRITE
    ldi r_temp, 0xD0
    rcall TWI_WRITE
    rcall TWI_START
    mov r_temp, r_addr_R
    rcall TWI_WRITE
    rcall TWI_READ_NACK
    ret

DELAY_MS:
    ldi r20, 255
    ldi r21, 40
DM_Loop:
    dec r20
    brne DM_Loop
    dec r21
    brne DM_Loop
    ret

DELAY_FAST:
    ldi r20, 255
    ldi r21, 5
DF_Loop:
    dec r20
    brne DF_Loop
    dec r21
    brne DF_Loop
    ret

; --- I2C Primitives ---
TWI_START:
    ldi r_temp, (1<<TWINT)|(1<<TWSTA)|(1<<TWEN)
    out TWCR, r_temp
WAIT_STA:
    in r_temp, TWCR
    sbrs r_temp, TWINT
    rjmp WAIT_STA
    ret

TWI_STOP:
    ldi r_temp, (1<<TWINT)|(1<<TWSTO)|(1<<TWEN)
    out TWCR, r_temp
    ret

TWI_WRITE:
    out TWDR, r_temp
    ldi r_temp, (1<<TWINT)|(1<<TWEN)
    out TWCR, r_temp
WAIT_WR:
    in r_temp, TWCR
    sbrs r_temp, TWINT
    rjmp WAIT_WR
    ret

TWI_READ_NACK:
    ldi r_temp, (1<<TWINT)|(1<<TWEN)
    out TWCR, r_temp
WAIT_RN:
    in r_temp, TWCR
    sbrs r_temp, TWINT
    rjmp WAIT_RN
    in r_temp, TWDR
    ret
    inc r16
    rjmp start
