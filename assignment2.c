#include <stdio.h>
#include <stdlib.h>

#include "pico/stdlib.h"
#include "hardware/pio.h"
#include "hardware/clocks.h"
#include "ws2812.pio.h"
#include "hardware/watchdog.h"

#define IS_RGBW true  // Will use RGBW format
#define NUM_PIXELS 1  // There is 1 WS2812 device in the chain
#define WS2812_PIN 28 // The GPIO pin that the WS2812 connected to

//----------------------Some useful global variables------------------------------------------------//
//for game itself


char answer[64]; // array that user input 
int level_number; // get the level number
int start_game; // 0 is select level, 1 is submit the answer.

int random_Index; // the index which is randomly selected by game

// for user
//int length_Of_Input_from_user = 0;
int index_of_user_input = 0;
//int select_correct_level; // the user select the valid level
int number_of_lives = 3;
int consecutive_correct_numbers = 0;


// Initialise a GPIO pin – see SDK for detail on gpio_init()
void asm_gpio_init(uint pin)
{
    gpio_init(pin);
}

// Set direction of a GPIO pin – see SDK for detail on gpio_set_dir()
void asm_gpio_set_dir(uint pin, bool out)
{
    gpio_set_dir(pin, out);
}

// Get the value of a GPIO pin – see SDK for detail on gpio_get()
bool asm_gpio_get(uint pin)
{
    return gpio_get(pin);
}

// Set the value of a GPIO pin – see SDK for detail on gpio_put()
void asm_gpio_put(uint pin, bool value)
{
    gpio_put(pin, value);
}

// Enable rising and falling-edge interrupt – see SDK for detail on gpio_set_irq_enabled()
void asm_gpio_set_irq(uint pin)
{
    gpio_set_irq_enabled(pin, GPIO_IRQ_EDGE_FALL, true);
    gpio_set_irq_enabled(pin, GPIO_IRQ_EDGE_RISE, true);
}
//---------------- watch dog part ----------------------------------------------------------------//

void watchdogUpdate()
{
    watchdog_update();
}

/* -------------------------------------------- RGB LED -------------------------------------------- */

// code for initialising RGB LED
/**
 * @brief Wrapper function used to call the underlying PIO
 *        function that pushes the 32-bit RGB colour value
 *        out to the LED serially using the PIO0 block. The
 *        function does not return until all of the data has
 *        been written out.
 *
 * @param pixel_grb The 32-bit colour value generated by urgb_u32()
 */
static inline void put_pixel(uint32_t pixel_grb)
{
    pio_sm_put_blocking(pio0, 0, pixel_grb << 8u);
}

/**
 * @brief Function to generate an unsigned 32-bit composit GRB
 *        value by combining the individual 8-bit paramaters for
 *        red, green and blue together in the right order.
 *
 * @param r     The 8-bit intensity value for the red component
 * @param g     The 8-bit intensity value for the green component
 * @param b     The 8-bit intensity value for the blue component
 * @return uint32_t Returns the resulting composit 32-bit RGB value
 */
static inline uint32_t urgb_u32(uint8_t r, uint8_t g, uint8_t b)
{
    return ((uint32_t)(r) << 8) |
           ((uint32_t)(g) << 16) |
           (uint32_t)(b);
}

//change the color of LED, three lives is green, two lives is orange, one live is yellow, 0 live is red   
//the default color is green
void lives_Colour_Change(){
    switch (number_of_lives){
    case 3:
        // indicate green
        printf("Three lives remaining\n");
        put_pixel(urgb_u32(0x00, 0x7F, 0x00));
        break;
    case 2:
        // indicate orange
        printf("Oops, two lives remaining\n");
        put_pixel(urgb_u32(0x2F, 0xC, 0x00));
        break;
    case 1:
        // indicate yellow
        printf("Warning, one live remaining\n");
        put_pixel(urgb_u32(0x7F, 0x7F, 0x00));
        break;
    case 0:
        // indicate red
        printf("Game over\n");
        put_pixel(urgb_u32(0x7F, 0x00, 0x00));
        break;
    default:
        // indicate green
        put_pixel(urgb_u32(0x00, 0x7F, 0x00));
        break;
    }
}


//-------------------------------------------- Button pressed Timing --------------------------------------------//


// Get a time point 
int get_time(){
    absolute_time_t time = get_absolute_time();
    return to_ms_since_boot(time);
}

// Find the time periond
int get_time_period(int ending_time, int starting_time){
    return (ending_time - starting_time);
}



//--------------------------------------- start game ----------------------------------------------------------//

void begin(){
    put_pixel(urgb_u32(0x00, 0x7F, 0x00)); // Set the RGB LED color to green
    number_of_lives = 3;
    consecutive_correct_numbers = 0;
}


char *code_alphabet_and_numbers[] = {
    ".-",    /* A */    "-...",  /* B */    "-.-.",  /* C */     "-..",   /* D */
    ".",     /* E */    "..-.",  /* F */    "--.",   /* G */    "....",  /* H */ 
    "..",    /* I */    ".---",  /* J */    "-.-",   /* K */    ".-..",  /* L */
    "--",    /* M */    "-.",    /* N */    "---",   /* O */    ".--.",  /* P */ 
    "--.-",  /* Q */    ".-.",   /* R */    "...",   /* S */    "-",     /* T */
    "..-",   /* U */    "...-",  /* V */    ".--",   /* W */    "-..-",  /* X */
    "-.--",  /* Y */    "--..",  /* Z */    "-----", /* 0 */    ".----", /* 1 */
    "..---", /* 2 */    "...--", /* 3 */    "....-", /* 4 */    ".....", /* 5 */
    "-....", /* 6 */    "--...", /* 7 */    "---..", /* 8 */    "----.", /* 9 */
};

char *alphabet_and_numbers[] = {
    "A", "B", "C", "D",
    "E", "F", "G", "H",
    "I", "J", "K", "L",
    "M", "N", "O", "P",
    "Q", "R", "S", "T",
    "U", "V", "W", "X",
    "Y", "Z", "0", "1",
    "2", "3", "4", "5",
    "6", "7", "8", "9",
};


//------------------------ match the input sequence against the lookup table and return the matching character --------------//

// char returnMatchingCharacter(){
//    for(int i = 0; i < table_SIZE; i++){
//         if(strcmp(answer, table[i].code) == 0){
//             return table[i].letter;
//         }
//     }
//     return -1;
// }

//------------------------read inputs from user and select the level/answer the question-------------------------------------------//

// initialise the input sequence
void initializeanswer(){
    for(int i = 0; i < 64; i++){
        answer[i] = 0;
    }
    //length_Of_Input_from_user = 0;
    index_of_user_input = 0;
}

void select_level(){
   start_game = 0; // user should select the level
}

void answer_question(){
    start_game = 1; // user should answer the question
}

int check_level_completion(){
    if(consecutive_correct_numbers == 5){
        return 1;
    }
    if (number_of_lives == 0){
        printf("\n");
        printf("||-------No Lives remaining--------||\n");
        printf("||---Sorry, you've lost the game---||\n");
        printf("\n");
        return 2;
    }
    return 0;
}


int level_selection(){
    if(consecutive_correct_numbers < 5){
        if (strcmp(answer, code_alphabet_and_numbers[27])==0){    // choose level 1
            printf("\n");
            printf("You choose the Level1 !!");
            return 1;
        }
        else if(strcmp(answer, code_alphabet_and_numbers[28])==0){    // choose level 2
            printf("\n");
            printf("You cannot go to level2");
            return 3;
        }
        else{
            printf("\n");
            printf("incorrect level entered");
            return 3;   // return 3 for invalid level
        }
    }
    else{
         if (strcmp(answer, code_alphabet_and_numbers[27])==0){    // choose level 1
            printf("\n");
            printf("You choose the Level1 !!");
            return 1;
        }
        else if(strcmp(answer, code_alphabet_and_numbers[28])==0){    // choose level 2
            printf("\n");
            printf("You choose the Level2 !!");
            return 2;
        }
        else{
            printf("\n");
            printf("incorrect level entered");
            return 3;   // return 3 for invalid level
        }
    }
}


// detect input from user
void keyPress(int input){
    switch(input){
        case 1:
            answer[index_of_user_input] = '.'; // add '.' to the array
            index_of_user_input++;
            printf(".");
            break;

        case 2:
             answer[index_of_user_input] = '-'; // add '-' to the array
             index_of_user_input++;
             printf("-");
             break;

        case 3:
            answer[index_of_user_input] = ' '; // add ' ' to the array
            index_of_user_input++;
            printf(" ");
            break;
        case 4: //'enter' two conditions, if start_game = 0; user should go to select level, otherwise, user should answer question.
             if (start_game == 0) {
                //inputComplete = 1;
                answer[index_of_user_input-1] = NULL;
                level_selection();
            } else if(start_game == 1){
                //inputComplete = 1;
                answer[index_of_user_input-1] = NULL;
                show_user_result();
                lives_Colour_Change(number_of_lives);
            }
            break;
    }
}

void show_user_result(){
    int result = checkLevel1_2();
    if (result == 0){
        correct_Level1and2_message();
    }else{
        incorrect_Level1and2_message();
    }
}


//---------------------------------level1 and level2 questions -----------------------------------------------------------------------------------//
// Convert characters to morse codes
int level1_question(){
    level_number = 1;
    int randomIndex = rand() % 36;
    random_Index = randomIndex;
    printf("||--------------------------------------------------||\n");
    printf("||--- Input the morse code of the below character---||\n");
    printf("||---                  %s                        ---||\n", alphabet_and_numbers[randomIndex]);
    printf("||---                  %s                        ---||\n",code_alphabet_and_numbers[randomIndex]);
    printf("||--------------------------------------------------||\n");
    watchdog_update();
    return random_Index;
}

// Convert morse code to characters
int level2_question(){
    level_number = 2;
    int randomIndex = rand() % 36;
    random_Index = randomIndex;
    printf("||--------------------------------------------||\n");
    printf("||--- Convert below character to morse code---||\n");
    printf("||---                %s                    ---||\n", alphabet_and_numbers[randomIndex]);
    printf("||--------------------------------------------||\n");
    watchdog_update();
    return random_Index;
}

int retrieveCurrentStage(){
    return level_number;
}

void updateStage(int newLevel){
    level_number = newLevel;
}

//--------------------------------------- check the result-------------------------------------//

int checkLevel1_2(){
    if(strcmp(answer, code_alphabet_and_numbers[random_Index]) == 0)
        return 0;
    else
        return 1;
}
//---------------------------check whether the player can continue--------------------------------//

bool continue_game(){
    if(number_of_lives > 0){
        return 1;
    }else{
        return 0;
    }
}

//--------------------------------------- Print the message-------------------------------------//

void welcome(){
    printf("\n");
    printf("In this game you will be given letters on the screen and you enter the morse equivalent \n");
    printf("You do this by pressing the GP21 button.\n");
    printf("Press the button for a short duration to enter a dot in morse, and press for a long duration to eneter a dash.\n");
    printf("You are given 3 lives and you lose a life if you get the answer wrong.\n");
    printf("If you lose all your lives, you will get a GAMER OVER and lose the game.\n");
    printf("To go to the next level, get 5 consequtive correct answers correct. \n");
}

void display_level_selection(){    
    printf("||---------------------------------------------------------------------------------------------------------------------------------||");
    printf("\n");
    printf("Now, choose the difficulty level\n");
    printf("For level 1, type in corresponding morse code for number 1(.----)\n");
    printf("For level 2, type in corresponding morse code for number 2(..---)\n");
    watchdog_update();
}

void correct_Level1and2_message(){
    consecutive_correct_numbers++;
    printf("||------------------You got the correct answer-----------------------||\n");
    printf("||---------You have answered %d questions correctly in a row.--------||\n", consecutive_correct_numbers);
    if(number_of_lives < 3){
        number_of_lives++;
        printf("||--------------Now you add a one life--------------------||\n");
    }
}

void incorrect_Level1and2_message(){
    consecutive_correct_numbers = 0;
    number_of_lives--;
    printf("||-------------Sorry, your answer is wrong----------------||\n");
    printf("||--------------Now you lose one life---------------------||\n");
}

void win_level1_or_2(){
    printf("\n");
    printf("||------------Complete current level: %d!-----------||\n", retrieveCurrentStage());
    printf("||--------------Your current information------------||\n");
    printf("||                Remaining Lives: %d               ||\n", number_of_lives);
    printf("||--------------------------------------------------||\n");
    printf("\n");
}

int main()
{
    // Initialise all STDIO
    stdio_init_all();

    // Initialise the PIO interface with the WS2812 code
    PIO pio = pio0;
    uint offset = pio_add_program(pio, &ws2812_program);
    ws2812_program_init(pio, 0, offset, WS2812_PIN, 800000, IS_RGBW);
    // Set the RGB LED color to blue
    put_pixel(urgb_u32(0x00, 0x00, 0x7F));

     // watchdog
    watchdog_enable(16777215, 0);

    // initialise all functions in arm
    main_asm();

    //show the welcome page
    welcome();

    // Should never get here due to infinite while-loop.
    return 0;
}
