;   PIC16F887
;   clock:20MHz
;
;   LCDを４ビットで制御
;
;   ＰＩＣのピン接続(PIC-MDX2-INCT-2.00)
;       RD4 LCD DB4
;       RD5 LCD DB5
;       RD6 LCD DB6
;       RD7 LCD DB7
;
;       RE1 LCD R/W (6:Read/Write)
;       RE0 LCD E   (5:Enable Signal)
;       RE2 LCD RS  (4:Register Select)

;
;   使用タイマ（プログラムループ）
;        15mS   LCDパワーオンリセット待ち
;         5mS   LCD初期化ルーチン
;         1mS   LCD初期化ルーチン
;        50uS   LCD初期化ルーチン，書き込み待ち
;


       LIST    P=PIC16F887
       INCLUDE P16F887.INC
       __CONFIG _CONFIG1, _INTRC_OSC_NOCLKOUT & _PWRTE_ON & _BOR_OFF &_WDT_OFF & _LVP_OFF

    CBLOCK  020h
    CNT
    CNTsmp          ; counter for sample time
    CNT15mS         ;15ｍＳカウンタ
    CNT5mS          ;5ｍＳカウンタ
    CNT1mS          ;1ｍＳカウンタ
    CNT50uS         ;50μＳカウンタ
    char            ;LCD表示データ
    CNTfig
    FIG1
    FIG10
    FIG100
    ENDC


; ==== LCD ============================
LCDDATA     EQU     08h     ; PORTD
LCDCTRL     EQU     09h     ; PORTE
; ---- LCD DATA bits ------------------
DB4         EQU     04h
DB5         EQU     05h
DB6         EQU     06h
DB7         EQU     07h
; ---- LCD control bits ---------------
RW          EQU     01h     ;LCD R/W
E           EQU     00h     ;LCD Enable
RS          EQU     02h     ;LCD Register Select
BUSY        EQU     07h     ;BUSY FLAG (PORTD,7)


; ==== Motor Driver ====================
MTRDRV      EQU     07h     ; PORTC
DUTYA       EQU     15h     ; CCPR1L
DUTYB       EQU     1Bh     ; CCPR2L
; ---- MTRDRV bits ---------------------
ASTBY       EQU     00h     ; LEFT MOTOR
APWM        EQU     02h
AIN1        EQU     04h
AIN2        EQU     05h
BSTBY       EQU     03h     ; RIGHT MOTOR
BPWM        EQU     01h
BIN1        EQU     06h
BIN2        EQU     07h


; ==== Photo Interrupter ===============
; value of black is 255 and white is 0
; -------------------------------------- 
PHOTINT     EQU     05h     ; PORTA
; ---- PHOTINT bits --------------------
PHOTA       EQU     00h     ; LEFT
PHOTB       EQU     01h     ; RIGHT


; ==================== 初期処理 =====================
    ORG     0
INIT
    BSF     OSCCON,IRCF0    ;内部クロック8MHz
    BSF     OSCCON,IRCF1    ;内部クロック8MHz
    BSF     OSCCON,IRCF2    ;内部クロック8MHz

    BSF     STATUS,RP0      ;バンク１に切替え
    MOVLW   b'00000000'
    MOVWF   TRISC
    MOVLW   b'00000000'     ;RD4-RD7は出力
    MOVWF   TRISD
    MOVLW   b'11111000'     ;RE0-RE2は出力
    MOVWF   TRISE
    BCF     STATUS,RP0      ;バンク０に切替え

    BSF     STATUS,RP0
    BSF     STATUS,RP1
    CLRF    ANSEL           ;PORTAはデジタルI/O
    CLRF    ANSELH          ;PORTEはデジタルI/O
    BCF     STATUS,RP0
    BCF     STATUS,RP1

    CLRF    PORTC
    CLRF    PORTD
    CLRF    PORTE

    CALL    LCD_init
    CALL    ADC_INIT
    CALL    MOTOR_INIT


    CALL    LCD_home        ;カーソルを１行目の先頭に
    MOVLW   'H'
    CALL    LCD_write
    MOVLW   'e'
    CALL    LCD_write
    MOVLW   'l'
    CALL    LCD_write
    MOVLW   'l'
    CALL    LCD_write
    MOVLW   'o'
    CALL    LCD_write
    MOVLW   ','
    CALL    LCD_write

    CALL    LCD_2line       ;カーソルを２行目の先頭に
    MOVLW   'w'
    CALL    LCD_write
    MOVLW   'o'
    CALL    LCD_write
    MOVLW   'r'
    CALL    LCD_write
    MOVLW   'l'
    CALL    LCD_write
    MOVLW   'd'
    CALL    LCD_write
    MOVLW   '!'
    CALL    LCD_write

    CLRF    PORTD
    CLRF    PORTE

    MOVLW   D'200'
    MOVWF   CNT
    CALL    wait15ms
    DECFSZ  CNT,F
    GOTO    $-2
    CALL    LCD_clear

    CALL    MT_A_FW         ; motor A is forward
    CALL    MT_B_FW         ; motor B is forward

; ==================== メイン処理 =====================
MAINLP
    CALL    LCD_home
    MOVLW   'A'
    CALL    LCD_write
    MOVLW   ':'
    CALL    LCD_write

    CALL    READ_PHOTA          ; black is 255 and white is 0
    MOVWF   DUTYA               ; set motor A duty cycle
    CALL    BCD
    MOVLW   30H
    ADDWF   FIG100,W
    CALL    LCD_write
    MOVLW   30H
    ADDWF   FIG10,W
    CALL    LCD_write
    MOVLW   30H
    ADDWF   FIG1,W
    CALL    LCD_write


    CALL    LCD_2line
    MOVLW   'B'
    CALL    LCD_write
    MOVLW   ':'
    CALL    LCD_write

    CALL    READ_PHOTB          ; black is 255 and white is 0
    MOVWF   DUTYB               ; set motor B duty cycle
    CALL    BCD
    MOVLW   30H
    ADDWF   FIG100,W
    CALL    LCD_write
    MOVLW   30H
    ADDWF   FIG10,W
    CALL    LCD_write
    MOVLW   30H
    ADDWF   FIG1,W
    CALL    LCD_write

    GOTO    MAINLP

;*****************
;* Motor Library *
;*****************
;================= 初期化 ======================
MOTOR_INIT
    BANKSEL TRISC
    CLRF    TRISC           ; motor driver
    BANKSEL PORTC
    CLRF    PORTC
    BANKSEL T2CON
    BSF     T2CON,TMR2ON
    BCF     T2CON,T2CKPS1   ; prescaler is 1
    BCF     T2CON,T2CKPS0   ; prescaler is 1
    MOVLW   0FFH
    BANKSEL PR2
    MOVWF   PR2
    BANKSEL CCP1CON
    MOVLW   B'00001100'     ; PWM mode 
    MOVWF   CCP1CON
    BANKSEL CCP2CON
    MOVLW   B'00001100'     ; PWM mode
    MOVWF   CCP2CON

    BANKSEL CCPR1L
    CLRF    CCPR1L          ; motor A duty cycle 0%
    BANKSEL CCPR2L
    CLRF    CCPR2L          ; motor B duty cycle 0%
    BANKSEL PORTC
    BCF     PORTC,AIN1      ; motor A is stop
    BCF     PORTC,AIN2
    BCF     PORTC,BIN1      ; motor B is stop
    BCF     PORTC,BIN2
    BSF     PORTC,ASTBY
    BSF     PORTC,BSTBY
    RETURN

MT_A_FW
    BANKSEL PORTC
    BSF     PORTC,AIN1
    BCF     PORTC,AIN2
    RETURN

MT_A_BW
    BANKSEL PORTC
    BCF     PORTC,AIN1
    BSF     PORTC,AIN2
    RETURN

MT_A_ST
    BANKSEL PORTC
    BCF     PORTC,AIN1
    BCF     PORTC,AIN2
    RETURN

MT_A_BK
    BANKSEL PORTC
    BSF     PORTC,AIN1
    BSF     PORTC,AIN2
    RETURN

MT_B_FW
    BANKSEL PORTC
    BSF     PORTC,BIN1
    BCF     PORTC,BIN2
    RETURN

MT_B_BW
    BANKSEL PORTC
    BCF     PORTC,BIN1
    BSF     PORTC,BIN2
    RETURN

MT_B_ST
    BANKSEL PORTC
    BCF     PORTC,BIN1
    BCF     PORTC,BIN2
    RETURN

MT_B_BK
    BANKSEL PORTC
    BSF     PORTC,BIN1
    BSF     PORTC,BIN2
    RETURN

SPEEDA
    BANKSEL DUTYA
    MOVWF   DUTYA
    RETURN
    
SPEEDB
    BANKSEL DUTYB
    MOVWF   DUTYB
    RETURN
    

;***************
;* ADC Library *
;***************
;================= 初期化 ======================
ADC_INIT
    BANKSEL ADCON1
    BCF     ADCON1,ADFM     ; left justify
    BCF     ADCON1,VCFG1    ; Vss
    BCF     ADCON1,VCFG0    ; Vdd
    BANKSEL TRISA
    BSF     TRISA,0         ; PHOTA
    BSF     TRISA,1         ; PHOTB
    BANKSEL ADCON0
    BSF     ADCON0,ADCS1    ; Fosc/32
    BCF     ADCON0,ADCS0    ; Fosc/32
    BSF     ADCON0,ADON     ; A/D On
    BCF     ADCON0,CHS3     ; AN0 or AN1
    BCF     ADCON0,CHS2     ; AN0 or AN1
    BCF     ADCON0,CHS1     ; AN0 or AN1
    BANKSEL PORTA
    
    RETURN  


;================= Read Data ======================
; return Wreg
;
READ_PHOTA
    BANKSEL ADCON0
    BCF     ADCON0,CHS0     ; AN0

    GOTO    READ_PHOTINT
    
READ_PHOTB
    BANKSEL ADCON0
    BSF     ADCON0,CHS0     ; AN1

    GOTO    READ_PHOTINT
    
READ_PHOTINT
    MOVLW   D'13'           ; sample time (0.5us * 3cycle * 13 = 19.5us) 
    MOVWF   CNTsmp
    DECFSZ  CNTsmp,F
    GOTO    $-1

    BSF     ADCON0,GO
    BTFSC   ADCON0,GO
    GOTO    $-1
    BANKSEL ADRESH
    MOVF    ADRESH,W

    BANKSEL PORTA

    RETURN



;***************
;* LCD Library *
;***************
;================= LCD表示をクリアする ===================
LCD_clear
    MOVLW   01h
    CALL    LCD_command
    RETURN

;================= LCDのカーソル位置を先頭に戻す =========
LCD_home
    MOVLW   02h
    CALL    LCD_command
    RETURN

;================= LCDのカーソル位置を２行目の先頭に =====
LCD_2line
    MOVLW   0C0h
    CALL    LCD_command
    RETURN

;================= LCDのディスプレイをＯＮにする =========
LCD_on
    MOVLW   0Ch
    CALL    LCD_command
    RETURN

;================= LCDのディスプレイとカーソルをＯＮにする ==
LCD_on_cur
    MOVLW   0Eh
    CALL    LCD_command
    RETURN

;================= LCDのディスプレイをＯＦＦにする =======
LCD_off
    MOVLW   08h
    CALL    LCD_command
    RETURN

;================= LCDにデータを送る =====================
LCD_write
    MOVWF   char
    CALL    LCD_BF_wait ;LCD busy 解除待ち
    ;CALL   wait50us

    BCF     PORTE,RW    ;R/W=0(Write)
    BSF     PORTE,RS    ;RS=1(Data)

    MOVLW   00Fh        ;PORTDの上位４ビットを
    ANDWF   PORTD,F     ;　クリア
    MOVF    char,W      ;上位
    ANDLW   0F0h        ;４ビットを
    IORWF   PORTD,F     ;PORTD(7-4)にセット（PORTD(3-0)はそのまま）
    BSF     PORTE,E     ;LCDにデータ書き込み
    NOP
    BCF     PORTE,E

    MOVLW   00Fh        ;PORTDの上下位４ビットを
    ANDWF   PORTD,F     ;　クリア
    SWAPF   char,W      ;下位
    ANDLW   0F0h        ;4ビットを
    IORWF   PORTD,F     ;PORTD(7-4)にセット（PORTD(3-0)はそのまま）
    BSF     PORTE,E     ;LCDにデータ書き込み
    NOP
    BCF     PORTE,E

    RETURN

;================= LCDにコマンドを送る ===================
LCD_command
    MOVWF   char
    CALL    LCD_BF_wait ;LCD busy 解除待ち

    BCF     PORTE,RW    ;R/W=0(Write)
    BCF     PORTE,RS    ;RS=0(Command)

    MOVLW   00Fh        ;PORTDの上位４ビットを
    ANDWF   PORTD,F     ;　クリア
    MOVF    char,W      ;上位
    ANDLW   0F0h        ;４ビットを
    IORWF   PORTD,F     ;PORTD(7-4)にセット（PORTD(3-0)はそのまま）
    BSF     PORTE,E     ;LCDにデータ書き込み
    NOP
    BCF     PORTE,E

    MOVLW   00Fh        ;PORTDの上位４ビットを
    ANDWF   PORTD,F     ;　クリア
    SWAPF   char,W      ;下位
    ANDLW   0F0h        ;４ビットを
    IORWF   PORTD,F     ;PORTD(7-4)にセット（PORTB(3-0)はそのまま）
    BSF     PORTE,E     ;LCDにデータ書き込み
    NOP
    BCF     PORTE,E

    RETURN

;================= LCD Busy 解除待ち ========================
LCD_BF_wait
    BCF     PORTE,E     
    BCF     PORTE,RS        ;RS=0(Control)
    BSF     PORTE,RW        ;R/W=1(Read) Busy Flag read

    BSF     STATUS,RP0      ;バンク１に切替え
    MOVLW   0FFh
    MOVWF   TRISD           ;RD0-7は入力
    BCF     STATUS,RP0      ;バンク０に切替え
    BSF     PORTE,E         ;LCD上位４ビット読み込み
    NOP
    BTFSS   PORTD,BUSY      ;LCD Busy ?
    GOTO    LCD_BF_wait1    ; No
    BCF     PORTE,E
    NOP
    BSF     PORTE,E         ;LCD下位４ビット読み飛ばし
    NOP
    BCF     PORTE,E
    GOTO    LCD_BF_wait

LCD_BF_wait1
    BSF     PORTE,E         ;LCD下位４ビット読み飛ばし
    NOP
    BCF     PORTE,E
    BSF     STATUS,RP0      ;■バンク１に切替え
    MOVLW   000h            ;RD7-4は出力
    MOVWF   TRISD
    BCF     STATUS,RP0      ;■バンク０に切替え

    RETURN

;================= LCD初期化 ================================
LCD_init
    CALL    wait15ms    ;15mS待つ
    BCF     PORTE,RW    ;R/W=0
    BCF     PORTE,RS    ;RS=0
    BCF     PORTE,E     ;E=0
    CALL    wait15ms    ;15mS待つ
    
    MOVLW   00Fh        ;PORTDの下位４ビットを
    ANDWF   PORTD,W     ;取り出す（変更しないように）
    IORLW   030h        ;上位４ビットに'３'をセット
    MOVWF   PORTD
    BSF     PORTE,E     ;ファンクションセット（１回目）
    NOP
    BCF     PORTE,E
    CALL    wait5ms     ;5mS待つ

    MOVLW   00Fh        ;PORTDの下位４ビットを
    ANDWF   PORTD,W     ;取り出す（変更しないように）
    IORLW   030h        ;上位４ビットに'３'をセット
    MOVWF   PORTD
    BSF     PORTE,E     ;ファンクションセット（２回目）
    NOP
    BCF     PORTE,E
    CALL    wait5ms     ;5mS待つ

    MOVLW   00Fh        ;PORTDの下位４ビットを
    ANDWF   PORTD,W     ;取り出す（変更しないように）
    IORLW   030h        ;上位４ビットに'３'をセット
    MOVWF   PORTD
    BSF     PORTE,E     ;ファンクションセット（３回目）
    NOP
    BCF     PORTE,E
    CALL    wait5ms     ;5mS待つ

    MOVLW   00Fh        ;PORTDの下位４ビットを
    ANDWF   PORTD,W     ;取り出す（変更しないように）
    IORLW   020h        ;４ビットモード
    MOVWF   PORTD       ;に
    BSF     PORTE,E     ;設定
    NOP
    BCF     PORTE,E
    CALL    wait1ms     ;1mS待つ

    MOVLW   028h        ;４ビットモード，２行表示，７ドット
    CALL    LCD_command
    CALL    LCD_off     ;ディスプレイＯＦＦ
    CALL    LCD_clear   ;LCDクリア
    MOVLW   06h         ;
    CALL    LCD_command ;カーソルモードセット (Increment)
    CALL    LCD_on      ;ディスプレイＯＮ，カーソルＯＦＦ
    RETURN

;================= 15mS WAIT ================================
wait15ms
    MOVLW   d'3'
    MOVWF   CNT15mS
wait15ms_loop
    CALL    wait5ms
    DECFSZ  CNT15mS,F
    GOTO    wait15ms_loop
    RETURN

;================= 5mS WAIT =================================
wait5ms
    MOVLW   d'100'
    MOVWF   CNT5mS
wait5ms_loop
    CALL    wait50us
    DECFSZ  CNT5mS,F
    GOTO    wait5ms_loop
    RETURN

;================= 1mS WAIT =================================
wait1ms
    MOVLW   d'20'
    MOVWF   CNT1mS
wait1ms_loop
    CALL    wait50us
    DECFSZ  CNT1mS,F
    GOTO    wait1ms_loop
    RETURN

;================= 50μS WAIT ===============================
wait50us
    ; １サイクル（４クロック）：０．５μＳ
    ; ５０μＳ＝０．５μＳ×１００サイクル

    MOVLW   d'31'       ;1
    MOVWF   CNT50uS     ;1
    NOP                 ;1
    NOP                 ;1
wait50us_loop
    DECFSZ  CNT50uS,F   ;1
    GOTO    wait50us_loop   ;2
    RETURN              ;2+1

;==== BCD transform ===================
BCD
    MOVWF   FIG1
    CLRF    FIG10
    CLRF    FIG100
    MOVLW   D'100'
FIG100_LP
    SUBWF   FIG1,F
    BTFSS   STATUS,C
    GOTO    FIG10_INIT
    INCF    FIG100,F
    GOTO    FIG100_LP

FIG10_INIT
    ADDWF   FIG1,F
    MOVLW   D'10'
FIG10_LP
    SUBWF   FIG1,F
    BTFSS   STATUS,C
    GOTO    FIG1_INIT
    INCF    FIG10,F
    GOTO    FIG10_LP

FIG1_INIT
    ADDWF   FIG1,F
    RETURN

    END
