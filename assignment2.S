#include "hardware/regs/addressmap.h"
#include "hardware/regs/io_bank0.h"
#include "hardware/regs/timer.h"
#include "hardware/regs/m0plus.h"

.syntax unified                                                 @ Use unified assembly syntax
.cpu    cortex-m0plus                                           @ Specify Cortex M0+ CPU type
.thumb                                                          @ Use Thumb assembly for RP2040
.global main_asm                                                @ Make main_asm function global to provide program starting address to the linker
.align 4                                                        @ Align code to a 4-byte boundary

.equ    DFLT_STATE_STRT, 1                                      @ Define default value to start flashing
.equ    DFLT_STATE_STOP, 0                                      @ Define default value to stop flashing
.equ    DFLT_ALARM_TIME, 2000000                                @ Define default alarm timeout value
.equ    SLEEP_TIME, 4000

.equ    GPIO_BTN_RISE_MSK, 0x00400000                           @ Define bitmask for rising-edge event on GP21
.equ    GPIO_BTN_FALL_MSK, 0x00800000                           @ Define bitmask for falling-edge event on GP21

.equ    GPIO_BTN,  21                                           @ Define GPIO pin for the button
.equ    GPIO_LED_PIN, 25                                        @ Define GPIO pin for the built-in LED

.equ    DOT, 255                                                @ Define input time for a dot (between 0 and 255 ms)
.equ    DASH_TIME, 250000                                       @ Define input time for a dash (255 ms and greater)

.equ    GPIO_DIR_IN,   0                                        @ Define input direction for a GPIO pin
.equ    GPIO_DIR_OUT,  1                                        @ Define output direction for a GPIO pin

.equ    GPIO_ISR_OFFSET, 0x74                                   @ Define offset for GPIO interrupt number 13 (vector table entry 29)
.equ    ALRM_ISR_OFFSET, 0x40                                   @ Define offset for ALARM0 interrupt number 0 (vector table entry 16)

@ Entry point for the assembly portion of the program
main_asm:

    bl      init_btns                                           @ Call init_btns subroutine to set up rising and falling-edge interrupts
    bl      install_gpio_isr                                    @ Call install_gpio_isr subroutine to initialize buttons
    bl      install_alrm_isr                                    @ Call install_alrm_isr subroutine to initialize alarm interrupts

@ Game logic and flow starts here
begin_game:
    movs    r4, #0                                             
    eors    r2, r2                                             
    bl      display_level_selection                              @ Display message for level choosing
    bl      select_level                                        @ Set selecting_level=true

wait_for_level:
    bl      stage_choice                                         @ Enter the level number in morse code
    cmp     r4, #1
    bne     wait_for_level                                      @ Wait until an input entered
    bl      answer_question

Game_Start:
    cmp     r4, #1                                              
    bne     resume_game                                         
    eors    r4, r4                                              @ else
    bl      initializeanswer                                    @ Initialize array
    bl      retrieveCurrentStage                                
    cmp     r0, #1
    beq     l1
    cmp     r0, #2
    beq     l2
    cmp     r0, #3
    beq     finish
@ Call to display level 1 question
l1:
    bl      level1_question                                                            
    b       finish_level_choosing
@ Call to display level 2 question
l2:
    bl      level2_question                                    
    b       finish_level_choosing

finish_level_choosing:
    movs    r6, #3        @ Initialize r6 to show whether a dot (0) or dash (1) has been pressed                                      
    movs    r5, #0         @ Initialize r5 to show how many interrupts/seconds have passed                                     
resume_game:
    bl      set_alarm        @ Call to set the alarm                                    
    wfi                       @ Wait for alarm/gpio interrupt                                  
    bl      input_capture    @ Call to insert the user input into the input array
    ldr     r3, =3             @ Load 3 into r3                               
    cmp     r6, r3               @ Check if input sequence has been started, i.e., the button was pressed                                
    beq     bypass                @ If not pressed, skip next instructions                               
    eors    r6, r6                 @ Reset r6, which shows whether a dot (0) or dash (1) has been pressed                          
bypass:
    bl      check_level_completion   @ Call to check level completion
    ldr     r3, =1 
    cmp     r0, r3
    beq     done
    cmp     r0, #2
    beq     begin_game
    b       Game_Start               @ Loop back up to start                                           
finish:
done:
    bl      retrieveCurrentStage     @ Call to get current level
     ldr    r3, =1   
    cmp     r0, r3
    beq     donel1
	
    ldr     r3, =2
    cmp     r0, r3
    beq     donel2

donel1:
    bl      win_level1_or_2
    movs    r0, #2
    bl      updateStage        @ Call to update stage
    b       transition
donel2:
    bl     win_level1_or_2     @ Call to win level 1 or 2
    movs    r0, #3
    bl      updateStage        @ Call to update stage
    b       transition

transition:
    bl      begin             @ Call to begin
    b       Game_Start        @ Branch to Game_Start


stage_choice:
Push    {lr}                                                    

    bl      initializeanswer                                
    movs    r6, #3            @ Initialize r6 to show whether a dot (0) or dash (1) has been pressed                                          
    eors    r5, r5              @ Initialize r5 to show how many interrupts/seconds have passed                                 
    
loop:
    bl      set_alarm          @ Call to set the alarm                                    
    wfi                        @ Wait for alarm/gpio interrupt                                        
    bl      input_capture      @ Call to insert the user input into the input array                                   
    ldr     r3, =3 
    cmp     r6, r3              @ Check if input sequence has been started, i.e., the button was pressed                                   
    beq     bypass1              @ If not pressed, skip next instructions                                 
    eors    r6, r6               @ Reset r6, which shows whether a dot (0) or dash (1) has been pressed                              
bypass1:
    ldr     r3, =2 
    cmp     r5, r3               @ Loop if the input is not completed                                         
    bne     loop

    cmp     r0, #1                @ Compare r0 to 1
    beq     lvl1                   @ If equal, branch to lvl1
    ldr     r3, =2                   @ Load 2 into r3
    cmp     r0, r3
    beq     lvl2
    ldr     r3, =2
    cmp     r0, r3
    beq     invalidLevelInput         @ If equal, branch to invalidLevelInput

lvl1:
    ldr     r0, =1                      @ Load 1 into r0
    b       level_choice_received        @ Branch to level_choice_received

lvl2:
    ldr     r0, =2  
    b       level_choice_received

invalidLevelInput:
    b       begin_game           @ Branch to begin_game

level_choice_received:

    bl      updateStage                                          
    bl      initializeanswer                                 
    movs    r4, #1
pop     {pc}                                                

@ Gets the user input 
input_capture:
    Push    {lr}                                                
    
    ldr     r3, =1 
    cmp     r5, r3   @ Compare r5 to r3                                           
    beq     space    @ Compare r5 to r3
    ldr     r3, =2   @ Load 2 into r3                                       
    cmp     r5, r3                                              
    beq     press    @ If equal, branch to press                                         
    cmp     r6, #1       @ If equal, branch to dot                                      
    beq     dot                                                
    cmp     r6, #2                                             
    beq     dash      @ If equal, branch to dash                                             
    b       select    @ Branch to select                                   

dot:
    ldr     r0, =1     @ Load 1 into r0 (1 = ".")                                          
    bl      keyPress     @ Call to add dot to input sequence                                   
    b       select         @ Branch to select                             

dash:
    ldr     r0, =2      @ Load 2 into r0 (2 = "-")                                             
    bl      keyPress     @ Call to add dash to input sequence                                   
    b       select        @ Branch to select                               

space:
    ldr     r0, =3       @ Load 3 into r0 (3 = " ")                                         
    bl      keyPress    @ Call to add space to input sequence                                                                     
    b       select      @ Branch to select                                 

press:
    ldr     r0, =4    @ Load 4 into r0 (4 = "enter")                                          
    bl      keyPress  @ Call to delete last space in input & set input to complete                                        
    movs    r4, #1      @ Set r4 to 1                                        
select:
    pop     {pc}      @ Pop the link register                                          


@ Subroutine used to setup falling-edge interrupts
init_btns:
    push    {lr}                                                @ Store the link register to the stack as we will call the init_btns subroutine   

    movs    r0, #GPIO_BTN                                       @ This value is the button pin on the PI PICO board
    bl      asm_gpio_init                                       @ Call the subroutine to initialise the GPIO pin specified by r0
    movs    r0, #GPIO_BTN                                       @ This value is the "enter button" pin on the PI PICO board
    movs    r1, #GPIO_DIR_IN                                    @ We want this GPIO pin to be setup as an input pin
    bl      asm_gpio_set_dir                                    @ Call the subroutine to set the GPIO pin specified by r0 to state specified by r1
    movs    r0, #GPIO_BTN                                       @ This value is the button pin on the PI PICO board
    bl      asm_gpio_set_irq                                    @ Call this subroutine to enable rising and falling-edge interrupt on the pin specified by r0

    pop     {pc}                                                @ Pop the link register from the stack to the program counter


@ Enable alarm timer interrupts and set an alarm
set_alarm:
    ldr     r0, =DFLT_ALARM_TIME    @ Load the default alarm time into r0
    ldr     r2, =TIMER_BASE         
    ldr     r3, =TIMER_TIMELR_OFFSET
    adds    r1, r2, r3              
    ldr     r2, [r1]                 @ Load the current timer count into r2
    adds    r2, r2, r0               @ Add the default alarm time to the current timer count
    str     r2, [r1]                 @ Store the updated timer count back into (TIMER_BASE + TIMER_TIMELR_OFFSET) register
    ldr     r0, =TIMER_BASE
    ldr     r3, =TIMER_ALARM0_OFFSET
    adds    r1, r0, r3
    str     r2, [r1]                @ Store the updated timer count into the timer alarm register
    ldr     r1, =TIMER_BASE
    ldr     r3, =TIMER_INTE_OFFSET
    adds    r1, r1, r3
    movs    r2, #1                   @ Load the value 1 into r2
    str     r2, [r1]                 @ Enable the timer alarm interrupt by writing 1 to the timer interrupt enable register
    bx      lr                        @ Return from the subroutine


    
@ Sets up the alrm_isr in the RAM vector table and enables the correct interrupt
install_alrm_isr:
    ldr     r2, =PPB_BASE
    ldr     r3, =M0PLUS_VTOR_OFFSET
    add     r2, r2, r3
    movs    r1, #1
    ldr     r1, [r2]
    movs    r2, #ALRM_ISR_OFFSET
    add     r2, r1
    ldr     r0, =alrm_isr
    str     r0, [r2]
    movs    r0, #1
    ldr     r2, =PPB_BASE
    ldr     r3, =M0PLUS_NVIC_ICPR_OFFSET
    add     r2, r2, r3
    str     r0, [r2]
    ldr     r2, =PPB_BASE
    ldr     r3, =M0PLUS_NVIC_ISER_OFFSET
    add     r2, r2, r3
    str     r0, [r2]
    bx      lr


@ Service the pending interrupt from the ALARM0 TIMER
.thumb_func 
alrm_isr:
    push    {lr}                        @ Store the link register to the stack as we will call nested subroutines

    movs    r0, #1                                  @clear interupt
    ldr     r2, =TIMER_BASE
    ldr     r3, =TIMER_INTR_OFFSET
    add     r2, r2, r3
    str     r0, [r2]
    cmp     r7, #0                      @ If there is a time stored in r7, then the button is still being held
    bne     inputHandlingUnderway
    cmp     r6, #3
    beq     inputHandlingUnderway

    @ Add 1 to the number of iterations the timer has gone off in r5
    ldr     r3, =1
    add     r5, r5, r3

inputHandlingUnderway:
   b       exit                     @ Pop the link register from the stack to the program counter 

@ Sets up the gpio_isr in the RAM vector table and enables the correct interrupt
install_gpio_isr:
    ldr     r3, =(PPB_BASE)                             @ Load the base address of the PPB into r3
    ldr     r1, =(M0PLUS_VTOR_OFFSET)                   @ Load the offset for the VTOR into r1
    adds    r3, r1                                      @ Add the offset to the base address to get the address of the interrupt vector table
    ldr     r1, [r3]                                    @ Load the value at the address of the interrupt vector table into r1
    ldr     r3, =GPIO_ISR_OFFSET                        @ Load the offset for the GPIO interrupt into r3
    adds    r3, r3, r1                                  @ Add the offset to the address of the interrupt vector table to get the address of the GPIO interrupt handler
    ldr     r0, =gpio_isr                               @ Load the address of the ISR_gpio subroutine into r0
    str     r0, [r3]                                    @ Store the address of the ISR_gpio subroutine at the address of the GPIO interrupt handler in the interrupt vector table
    ldr     r3, =(PPB_BASE)                             @ Load the base address of the PPB into r3
    ldr     r1, =(M0PLUS_NVIC_ICPR_OFFSET)                   @ Load the offset for the VTOR into r1
    adds    r3, r1 
    ldr     r1, =1                                       @ Load the value 1 into r1
    lsls    r1, #13                                     @ Shift the value 1 left by 13 bits to clear the interrupt flag for the GPIO
    str     r1, [r3]                                    @ Clear the interrupt flag for the GPIO
    ldr     r3, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)   @ Load the address of the NVIC_ISER register into r3
    
    str     r1, [r3]                                    @ Enable the GPIO interrupt
    bx      lr                                          @ Return from the interrupt handler                                         @ Exit subroutine

@ Service the pending interrupt from the GPIO
@ Returns the time difference between rising and falling edge in ms in r6
.thumb_func                                                     @ Required for all interrupt service routines
gpio_isr:
    push    {lr}                                                @ Store the link register to the stack as we will call the svc_isr routine
    ldr     r5, =0                                              @ Reset the interrupt count
    ldr     r2, =(IO_BANK0_BASE + IO_BANK0_PROC0_INTS2_OFFSET)  @ Read the interrupt status event from the (IO_BANK0_BASE + IO_BANK0_PROC0_INTS2_OFFSET) register
    ldr     r1, [r2]
    ldr     r0, =8192
    str     r0, [r2]
    ldr     r2,=GPIO_BTN_RISE_MSK
    CMP     r1, r2                                              @ Detect if it is a rising edge
    beq     handleRisingEdge
    ldr     r2, =GPIO_BTN_FALL_MSK
    CMP     r1, r2                                              @ Detect if it is a falling edge
    beq     handleFallingEdge
    b       exit

handleRisingEdge: 
 ldr     r2, =IO_BANK0_BASE            @ Load the base address of GPIO bank 0
 ldr     r3, =IO_BANK0_INTR2_OFFSET    @ Load the offset of the interrupt register
 add     r2, r2, r3                    @ Compute the address of the interrupt register
 ldr     r1, =GPIO_BTN_RISE_MSK        @ Load the mask for rising edge detection
 str     r1, [r2]             @ Disable the pending interrupt by writing the mask to the interrupt register
 bl      get_time             @ Get the current time
 movs    r7, r0               @ Store the start time in r7
 b       exit            @ Branch to end_input label


handleFallingEdge:
 ldr     r2, =IO_BANK0_BASE    @ Load the base address of GPIO bank 0
 ldr     r3, =IO_BANK0_INTR2_OFFSET    @ Load the offset of the interrupt register
 add     r2, r2, r3           @ Compute the address of the interrupt register
 ldr     r1, =GPIO_BTN_FALL_MSK    @ Load the mask for falling edge detection
 str     r1, [r2]             @ Disable the pending interrupt by writing the mask to the interrupt register
 bl      get_time             @ Get the current time
 movs    r1, r7              @ Load the start time
 bl      get_time_period     @ Compute the time period between the start time and current time
 movs    r7, r0              @ Store the time period in r7
 bl      watchdog_update     @ Update the watchdog timer
 movs    r0, r7              @ Move the time period to r0
 movs    r7, #0              @ Clear the time stored in r7
 cmp     r0, #DOT            @ Compare the time period with DOT duration
 blt     select_dot           @ If(time < 255ms), input is a dot
 bge     select_dash          @ If(time >= 255ms), input is a dash
 b       exit           @ Otherwise, input is complete

select_dot:
    ldr     r6, =1                                              @ 1 = "."
    b       exit

select_dash:
    ldr     r6, =2                                              @ 2 = "-"

exit:
    pop     {pc}                                                @ Exit ISR   
@ Set data alignment
.data
    .align 4
