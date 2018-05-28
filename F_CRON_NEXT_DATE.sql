
create or replace function  F_CRON_NEXT_DATE ( I_CRON_TAB  in varchar2
                                             , I_BASE_DATE in date
                                             ) return date is

/* ******************************************************************************************

    The F_CRON_NEXT_DATE returns the next available date from I_BASE_DATE according the rules by I_CRON_TAB
    See more: https://en.wikipedia.org/wiki/Cron
    It can handle 5 parts: minute hour day_of_month month day_of_week 
    and masks            : *   ?   n-m   /n   a,b,c,d

    Parameters:
    -----------
    I_CRON_TAB          a string contains the cron rule
    I_BASE_DATE         the base date and time. 

    Sample:
    -------
    select sysdate from dual
    select F_CRON_NEXT_DATE('/5 * * 10 4-5', sysdate) from dual        

    Result:
    -------
    2017.01.06 15:03:30 
    2017.10.05 00:00:00         

    History of changes
    yyyy.mm.dd | Version | Author         | Changes
    -----------+---------+----------------+-------------------------
    2017.01.06 |  1.0    | Ferenc Toth    | Created 

***************************************************************************************** */

    -- Pattern is a sequence of bits. 0 means "no", 1 means "yes". "Yes" means that is a good minute/hour/day/month to be the next one.
    type T_PATTERN       is table of number( 1 ) index by binary_integer; 

    V_CRON_TAB           varchar2( 4000 );  -- the input
    V_CRON_MINUTE        varchar2( 4000 );  -- the minute part of the input
    V_CRON_HOUR          varchar2( 4000 );  -- the hour part of the input
    V_CRON_MONTH_DAY     varchar2( 4000 );  -- the month day part of the input
    V_CRON_MONTH         varchar2( 4000 );  -- the month part of the input
    V_CRON_WEEK_DAY      varchar2( 4000 );  -- the week day part of the input

    V_MINUTE_PATTERN     T_PATTERN;
    V_HOUR_PATTERN       T_PATTERN;
    V_MONTH_DAY_PATTERN  T_PATTERN;
    V_MONTH_PATTERN      T_PATTERN;
    V_WEEK_DAY_PATTERN   T_PATTERN;

    V_NEXT_DATE          date;
    V_NEXT_MINUTE        number;        
    V_NEXT_HOUR          number;
    V_NEXT_MONTH_DAY     number;
    V_NEXT_WEEK_DAY      number;
    V_NEXT_MONTH         number;
    V_NEXT_YEAR          number;
    V_1_HOUR             number := 1/24;
    V_N                  number;

    ---------------------------------------------------------------------------------
    function GET_PART( I_STRING in varchar, I_POS in number ) return varchar2 is
    ---------------------------------------------------------------------------------
    -- returns with the I_POS.th part of the I_STRING. The PARTS are separated by Space character
        L_START     number := 0;   
        L_PART      varchar2( 4000 ); 
    begin   
        if I_POS > 1 then
            L_START := instr( I_STRING, ' ', 1, I_POS - 1 );
        end if;
        L_PART := substr( I_STRING, L_START + 1, instr( I_STRING, ' ', L_START + 1 ) - L_START - 1 );
        return nvl( L_PART, '*' );
    end;

    ---------------------------------------------------------------------------------
    function GET_NUMBER( I_STRING in varchar, I_FROM in number, I_DIRECTION in number ) return number is
    ---------------------------------------------------------------------------------
    -- returns with the number what is started from I_FROM to I_DIRECTION in I_STRING
        L_START     number := I_FROM;   
        L_STRING    varchar2( 400 ); 
    begin   
        if I_DIRECTION > 0 then
            loop
                exit when length( I_STRING ) < L_START or instr('0123456789', substr( I_STRING, L_START, 1 ) ) = 0;
                L_STRING := L_STRING || substr( I_STRING, L_START, 1 );
                L_START  := L_START + 1;
            end loop;
        else
            loop
                exit when L_START = 0 or instr('0123456789', substr( I_STRING, L_START, 1 ) ) = 0;
                L_STRING := substr( I_STRING, L_START, 1 ) || L_STRING ;
                L_START  := L_START - 1;
            end loop;
        end if;
        return to_number( L_STRING );
    end;

    ---------------------------------------------------------------------------------
    function GET_PATTERN( I_STRING in varchar, I_FROM in number, I_TO in number ) return T_PATTERN is
    ---------------------------------------------------------------------------------
    -- returns with a flag array where the 0 value means NO and 1 value means YES
    -- eg: '4-10', 1, 31 => 0001111111000000000000000000000
        L_PATTERN       T_PATTERN;
        L_NUMBER        number;
        L_FROM          number;
        L_TO            number;
    begin
        if I_STRING in ('*','?') then           -- if the rule is * or ? that means YES at every time
            for L_I in I_FROM..I_TO loop
                L_PATTERN( L_I ) := 1;
            end loop;
        else
            -- init the array to NO
            for L_I in I_FROM..I_TO loop
                L_PATTERN( L_I ) := 0;
            end loop;

            begin
                -- is it a simple number only? That's why we had to change , to ;
                L_NUMBER := to_number( I_STRING );
                if L_NUMBER >= I_FROM and L_NUMBER <= I_TO then
                    L_PATTERN( L_NUMBER ) := 1;
                end if;

            exception when others then

                -- /n means in every n.th time
                if instr(I_STRING, '/') > 0 then
                    L_NUMBER := GET_NUMBER( I_STRING, instr( I_STRING, '/' ) + 1, 1 );
                    for L_I in I_FROM..I_TO loop
                        if mod( L_I, L_NUMBER ) = 0 then
                            L_PATTERN( L_I ) := 1;
                        end if;
                    end loop;                    
                end if;

                -- n,m,o,p ... means a list of values
                if instr(I_STRING, ';') > 0 then
                    L_FROM := 1;
                    loop
                        L_NUMBER := GET_NUMBER( I_STRING, L_FROM, 1 );
                        exit when L_NUMBER is null;
                        L_PATTERN( L_NUMBER ) := 1;
                        L_FROM := instr(I_STRING, ';' ,L_FROM ) + 1;
                        exit when L_FROM = 1;
                    end loop;
                end if;

                --  n-m means an interval
                if instr(I_STRING, '-') > 0 then
                    L_TO    := GET_NUMBER( I_STRING, instr( I_STRING, '-' ) + 1,  1 );
                    L_FROM  := GET_NUMBER( I_STRING, instr( I_STRING, '-' ) - 1, -1 );
                    if L_TO >= L_FROM then
                        for L_I in L_FROM..L_TO loop
                            L_PATTERN( L_I ) := 1;
                        end loop;
                    else
                        for L_I in L_FROM..I_TO loop
                            L_PATTERN( L_I ) := 1;
                        end loop;
                        for L_I in I_FROM..L_TO loop
                            L_PATTERN( L_I ) := 1;
                        end loop;
                    end if;
                end if;

            end;

        end if;
        return L_PATTERN;
    end;

    ---------------------------------------------------------------------------------
    function GET_NEXT_DATE return date is
    ---------------------------------------------------------------------------------
    -- returns with the date value of the "NEXT" variables
    begin
        return to_date(   lpad( to_char( V_NEXT_YEAR      ), 4, '0')
                       || lpad( to_char( V_NEXT_MONTH     ), 2, '0')
                       || lpad( to_char( V_NEXT_MONTH_DAY ), 2, '0')
                       || lpad( to_char( V_NEXT_HOUR      ), 2, '0')
                       || lpad( to_char( V_NEXT_MINUTE    ), 2, '0'), 'YYYYMMDDHH24MI');
    exception when others then
        return null;
    end;

    ---------------------------------------------------------------------------------
    procedure SET_NEXT_PARTS is
    ---------------------------------------------------------------------------------
    -- split the next date to parts
    begin
        V_NEXT_MINUTE    := to_number( to_char( V_NEXT_DATE, 'MI'   ) );
        V_NEXT_HOUR      := to_number( to_char( V_NEXT_DATE, 'HH24' ) );
        V_NEXT_MONTH_DAY := to_number( to_char( V_NEXT_DATE, 'DD'   ) );
        V_NEXT_WEEK_DAY  := to_number( to_char( V_NEXT_DATE, 'D'    ) );
        V_NEXT_MONTH     := to_number( to_char( V_NEXT_DATE, 'MM'   ) );
        V_NEXT_YEAR      := to_number( to_char( V_NEXT_DATE, 'YYYY' ) );
    end;

    ---------------------------------------------------------------------------------
    function FULL_ZERO( I_PATTERN in T_PATTERN ) return boolean is
    ---------------------------------------------------------------------------------
    -- return true if every element is 0 in the pattern
    begin
        for L_I in I_PATTERN.first..I_PATTERN.last
        loop
            if I_PATTERN( L_I ) = 1 then
                return false;
            end if;
        end loop;
        return true;
    end;

    ---------------------------------------------------------------------------------
    function GET_PATTERN_STRING( I_PATTERN in T_PATTERN) return varchar2 is
    ---------------------------------------------------------------------------------
    -- for debugging
        L_STRING    varchar2(100);
    begin
        for L_I in I_PATTERN.first..I_PATTERN.last loop
            L_STRING := L_STRING || to_char( I_PATTERN( L_I ) );
        end loop;
        return L_STRING;
    end;
    ---------------------------------------------------------------------------------

    ---------------------------------------------------------------------------------
    procedure DEBUG is
    ---------------------------------------------------------------------------------
    begin
        dbms_output.put_line('YY:' ||V_NEXT_YEAR      );
        dbms_output.put_line('MM:' ||V_NEXT_MONTH     );
        dbms_output.put_line('DD:' ||V_NEXT_MONTH_DAY );
        dbms_output.put_line('WD:' ||V_NEXT_WEEK_DAY  );
        dbms_output.put_line('HH:' ||V_NEXT_HOUR      );
        dbms_output.put_line('MI:' ||V_NEXT_MINUTE    );
    end;


begin
    -- prepare CRON TAB
    V_CRON_TAB := I_CRON_TAB;
    loop
        exit when instr( V_CRON_TAB, '  ' ) = 0;
        V_CRON_TAB := replace( V_CRON_TAB, '  ', ' ' );
    end loop;
    V_CRON_TAB       := trim( V_CRON_TAB )||' ';
    V_CRON_TAB := replace( V_CRON_TAB, ',', ';' );  -- , could be a decimal symbol

    -- separate the cron string to parts
    V_CRON_MINUTE       := GET_PART( V_CRON_TAB, 1 );
    V_CRON_HOUR         := GET_PART( V_CRON_TAB, 2 );
    V_CRON_MONTH_DAY    := GET_PART( V_CRON_TAB, 3 );
    V_CRON_MONTH        := GET_PART( V_CRON_TAB, 4 );
    V_CRON_WEEK_DAY     := GET_PART( V_CRON_TAB, 5 );
    
    -- using those parts fill up the pattern arrays
    V_MINUTE_PATTERN    := GET_PATTERN( V_CRON_MINUTE   , 0, 59 );
    V_HOUR_PATTERN      := GET_PATTERN( V_CRON_HOUR     , 0, 23 );
    V_MONTH_DAY_PATTERN := GET_PATTERN( V_CRON_MONTH_DAY, 1, 31 );
    V_WEEK_DAY_PATTERN  := GET_PATTERN( V_CRON_WEEK_DAY , 1,  7 );
    V_MONTH_PATTERN     := GET_PATTERN( V_CRON_MONTH    , 1, 12 );

    V_NEXT_DATE      := I_BASE_DATE;
    SET_NEXT_PARTS;
    
    /*  debug   
    dbms_output.put_line('DATE:'||to_char(V_NEXT_DATE, 'yyyy.mm.dd hh24:mi') );
    dbms_output.put_line('CT MI:'||V_CRON_MINUTE    );
    dbms_output.put_line('CT HH:'||V_CRON_HOUR      );
    dbms_output.put_line('CT DD:'||V_CRON_MONTH_DAY );
    dbms_output.put_line('CT MM:'||V_CRON_MONTH     );
    dbms_output.put_line('CT WD:'||V_CRON_WEEK_DAY  );
    dbms_output.put_line('PA MM:'||GET_PATTERN_STRING( V_MONTH_PATTERN     ) );
    dbms_output.put_line('PA DD:'||GET_PATTERN_STRING( V_MONTH_DAY_PATTERN ) );
    dbms_output.put_line('PA HH:'||GET_PATTERN_STRING( V_HOUR_PATTERN      ) );
    dbms_output.put_line('PA MI:'||GET_PATTERN_STRING( V_MINUTE_PATTERN    ) );
    dbms_output.put_line('PA WD:'||GET_PATTERN_STRING( V_WEEK_DAY_PATTERN  ) );
    debug end */

    -- check the patterns
    if FULL_ZERO ( V_MINUTE_PATTERN    ) or
       FULL_ZERO ( V_HOUR_PATTERN      ) or   
       FULL_ZERO ( V_MONTH_DAY_PATTERN ) or   
       FULL_ZERO ( V_WEEK_DAY_PATTERN  ) or   
       FULL_ZERO ( V_MONTH_PATTERN     ) then
        return null;   -- something is wrong
    end if;


    -------------------------------------------
    -- find the first "1" month pattern:
    -------------------------------------------
    V_N := V_MONTH_PATTERN.count;
    loop
        exit when V_MONTH_PATTERN ( V_NEXT_MONTH ) = 1 or V_N = 0;
        V_NEXT_MONTH     := V_NEXT_MONTH + 1;  -- next month
        -- if the month has changed then we have to reset the other values
        V_NEXT_MINUTE    := 0;
        V_NEXT_HOUR      := 0;
        V_NEXT_MONTH_DAY := 1;
        V_N := V_N - 1;
        if V_NEXT_MONTH = 13 then
            V_NEXT_MONTH := 1;
            V_NEXT_YEAR  := V_NEXT_YEAR + 1;   
        end if;
    end loop;
    V_NEXT_DATE     := GET_NEXT_DATE; 
    V_NEXT_WEEK_DAY := to_number( to_char( V_NEXT_DATE, 'D' ) );
    -- DEBUG;


    -------------------------------------------------------------
    -- find the first "1" day, both month and week pattern:
    -------------------------------------------------------------
    loop
        exit when V_MONTH_DAY_PATTERN( V_NEXT_MONTH_DAY ) = 1 and V_WEEK_DAY_PATTERN( V_NEXT_WEEK_DAY ) = 1;
        V_NEXT_DATE      := V_NEXT_DATE + 1;   -- next day
        V_NEXT_MINUTE    := 0;
        V_NEXT_HOUR      := 0;
        V_NEXT_MONTH_DAY := to_number( to_char( V_NEXT_DATE, 'DD'   ) );
        V_NEXT_WEEK_DAY  := to_number( to_char( V_NEXT_DATE, 'D'    ) );
        V_NEXT_MONTH     := to_number( to_char( V_NEXT_DATE, 'MM'   ) );
        V_NEXT_YEAR      := to_number( to_char( V_NEXT_DATE, 'YYYY' ) );
    end loop;
    -- DEBUG;

    -------------------------------------------
    -- find the first "1" hour pattern:
    -------------------------------------------
    V_N := V_HOUR_PATTERN.count;
    loop
        exit when V_HOUR_PATTERN ( V_NEXT_HOUR ) = 1 or V_N = 0;
        V_NEXT_HOUR   := V_NEXT_HOUR + 1;
        V_NEXT_MINUTE := 0;
        V_N := V_N - 1;
        if V_NEXT_HOUR = 24 then
            V_NEXT_HOUR := 0;
            V_NEXT_DATE := GET_NEXT_DATE + 1;   
        end if;
    end loop;
    V_NEXT_DATE   := GET_NEXT_DATE; 
    -- DEBUG;

    -------------------------------------------
    -- find the first "1" minute pattern:
    -------------------------------------------
    V_N := V_MINUTE_PATTERN.count;
    loop
        exit when V_MINUTE_PATTERN ( V_NEXT_MINUTE ) = 1 or V_N = 0;
        V_NEXT_MINUTE := V_NEXT_MINUTE + 1;
        V_N := V_N - 1;
        if V_NEXT_MINUTE = 60 then
            V_NEXT_MINUTE := 0;
            V_NEXT_DATE   := GET_NEXT_DATE + V_1_HOUR; 
        end if;
    end loop;
    V_NEXT_DATE   := GET_NEXT_DATE; 
    -- DEBUG;

    return V_NEXT_DATE;

exception when others then
    return null;    -- something is wrong
end;
/
