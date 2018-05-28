
# CRON Next Date

## Oracle PL/SQL solution to get next date using CRON syntax

The **F_CRON_NEXT_DATE** function returns the next available date from **I_BASE_DATE** according the rules by **I_CRON_TAB**
See more: https://en.wikipedia.org/wiki/Cron

It can handle 5 parts: 
- minute 
- hour 
- day_of_month 
- month 
- day_of_week 

and masks : 
- \*   
- ?   
- n-m   
- /n   
- a,b,c,d

Parameters:

    I_CRON_TAB          a string contains the cron rule
    I_BASE_DATE         the base date and time. 

Sample:

    select sysdate from dual

    select F_CRON_NEXT_DATE('/5 * * 10 4-5', sysdate) from dual        

Results:

    2017.01.06 15:03:30 

    2017.10.05 00:00:00         

