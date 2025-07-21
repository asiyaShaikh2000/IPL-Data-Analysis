use ipl;
-- 2. What is the total number of runs scored in 1st season by RCB (bonus: also include the extra runs using the extra runs table)
SELECT SUM(COALESCE(b.Runs_Scored, 0) + COALESCE(e.Extra_Runs, 0)) AS total_runs
FROM ball_by_ball b
JOIN extra_runs e ON b.Match_Id = e.Match_Id 
JOIN matches m ON b.Match_Id = m.Match_Id
JOIN player_match pm ON b.Match_Id = pm.Match_Id 
WHERE m.Season_Id = 1
    AND pm.Team_Id = 2;
    
-- 3. How many players were more than the age of 25 during season 2014?
SELECT COUNT(DISTINCT p.Player_Id) AS players_above_25
FROM player p
JOIN player_match pm ON p.Player_Id = pm.Player_Id
JOIN matches m ON pm.Match_Id = m.Match_Id
WHERE m.season_id = 7
    AND TIMESTAMPDIFF(YEAR, p.DOB, '2014-01-01') > 25;

-- 4.How many matches did RCB win in 2013? 
select count(*) as rcb_wins_2013 from matches
where Season_Id = 7 and Match_Winner = 2;

-- 5.List the top 10 players according to their strike rate in the last 4 seasons
SELECT p.Player_Name,
    SUM(bbb.Runs_Scored) AS Total_Runs,
    COUNT(*) AS Balls_Faced,
    ROUND((SUM(bbb.Runs_Scored) * 100.0) / COUNT(*), 2) AS Strike_Rate
FROM ball_by_ball bbb
JOIN matches m ON bbb.Match_Id = m.Match_Id
JOIN season s ON m.Season_Id = s.Season_Id
JOIN player p ON bbb.Striker = p.Player_Id
WHERE s.Season_Year >= (SELECT MAX(Season_Year) - 3 FROM season)
GROUP BY p.Player_Name
HAVING COUNT(*) >= 50 
ORDER BY Strike_Rate DESC
LIMIT 10;

-- 6.What are the average runs scored by each batsman considering all the seasons?
SELECT p.Player_Name,
    ROUND(SUM(b.Runs_Scored) / COUNT(DISTINCT b.Match_Id), 2) AS average_runs
FROM ball_by_ball b
JOIN player p ON b.Striker = p.Player_Id
GROUP BY p.Player_Id, p.Player_Name
ORDER BY average_runs DESC;

-- 7.What are the average wickets taken by each bowler considering all the seasons?
SELECT p.Player_Name,
    ROUND(COUNT(w.Player_Out) / COUNT(DISTINCT m.Match_Id), 2) AS avg_wicket
FROM wicket_taken w
JOIN player_match pm ON w.Match_Id = pm.Match_Id
JOIN player p ON pm.Player_Id = p.Player_Id
JOIN  matches m ON w.Match_Id = m.Match_Id
GROUP BY  p.Player_Name
ORDER BY  avg_wicket DESC;

-- 8.List all the players who have average runs scored greater than the overall average and who have taken wickets greater than the overall average
WITH player_runs AS (
    SELECT 
        Striker AS Player_Id,
        SUM(Runs_Scored) AS total_runs,
        COUNT(DISTINCT Match_Id) AS matches_played,
        SUM(Runs_Scored) * 1.0 / COUNT(DISTINCT Match_Id) AS avg_runs
    FROM ball_by_ball
    GROUP BY Striker),
player_wickets AS (
    SELECT 
        b.Bowler AS Player_Id,
        COUNT(w.Player_Out) AS total_wickets,
        COUNT(DISTINCT b.Match_Id) AS matches_bowled,
        COUNT(w.Player_Out) * 1.0 / COUNT(DISTINCT b.Match_Id) AS avg_wickets
    FROM wicket_taken w
    JOIN ball_by_ball b ON w.Match_Id = b.Match_Id
	GROUP BY b.Bowler),
overall_averages AS (
    SELECT 
        AVG(r.avg_runs) AS overall_avg_runs,
        AVG(w.avg_wickets) AS overall_avg_wickets
    FROM player_runs r
    JOIN player_wickets w ON r.Player_Id = w.Player_Id),
combined AS (
    SELECT 
        r.Player_Id,
        r.avg_runs,
        w.avg_wickets
    FROM player_runs r
    JOIN player_wickets w ON r.Player_Id = w.Player_Id)
SELECT 
    c.Player_Id,
    c.avg_runs,
    oa.overall_avg_runs,
    c.avg_wickets,
    oa.overall_avg_wickets
FROM combined c
JOIN overall_averages oa
    ON c.avg_runs > oa.overall_avg_runs
    AND c.avg_wickets > oa.overall_avg_wickets;

-- 9.Create a table rcb_record table that shows the wins and losses of RCB in an individual venue.
drop table  if exists rcb_record;
CREATE TABLE rcb_record (
	Venue_Id int primary key,
    Venue_Name VARCHAR(450),
    Wins INT,
    Losses INT);
    
INSERT INTO rcb_record (Venue_Id,Venue_Name, Wins, Losses)
SELECT 
    Venue_Id,Venue_Name,
    SUM(CASE WHEN Match_Winner = 2 THEN 1 ELSE 0 END) AS Wins,
    SUM(CASE WHEN (Team_1 = 2 OR Team_2 = 2) 
                 AND Match_Winner IS NOT NULL 
                 AND Match_Winner <> 2 THEN 1
            ELSE 0
        END) AS Losses
FROM matches
JOIN venue using (Venue_Id)
WHERE Team_1 = 2 OR Team_2 = 2
GROUP BY Venue_Id,Venue_Name;
select * from rcb_record;

-- 10.What is the impact of bowling style on wickets taken?
SELECT 
    bs.Bowling_skill,
    COUNT(*) AS Total_Wickets
FROM wicket_taken wt
JOIN ball_by_ball bbb 
    ON wt.Match_Id = bbb.Match_Id 
    AND wt.Over_Id = bbb.Over_Id 
    AND wt.Ball_Id = bbb.Ball_Id 
    AND wt.Innings_No = bbb.Innings_No
JOIN player p ON bbb.Bowler = p.Player_Id
JOIN bowling_style bs ON p.Bowling_skill = bs.Bowling_Id
GROUP BY bs.Bowling_skill
ORDER BY Total_Wickets DESC;

-- 11.Write the SQL query to provide a status of whether the performance of the team is better than the previous year's performance on the basis of the number of runs scored by the team in the season and the number of wickets taken 
WITH team_season_stats AS (
    SELECT 
        s.Season_Year,
        b.Team_Batting AS Team_Id,
        SUM(b.Runs_Scored) AS total_runs,
        COUNT(w.Player_Out) AS total_wickets
    FROM ball_by_ball b
    JOIN matches m ON b.Match_Id = m.Match_Id
    JOIN season s ON m.Season_Id = s.Season_Id
    LEFT JOIN wicket_taken w 
        ON b.Match_Id = w.Match_Id 
        AND b.Over_Id = w.Over_Id 
        AND b.Ball_Id = w.Ball_Id
    GROUP BY s.Season_Year, b.Team_Batting),
yearly_comparison AS (
    SELECT 
        curr.Season_Year,t.Team_Name,curr.Team_Id,curr.total_runs,curr.total_wickets,
        prev.total_runs AS prev_total_runs,
        prev.total_wickets AS prev_total_wickets,
        CASE 
            WHEN curr.total_runs > prev.total_runs AND curr.total_wickets > prev.total_wickets THEN 'Improved'
            WHEN curr.total_runs < prev.total_runs AND curr.total_wickets < prev.total_wickets THEN 'Declined'
            ELSE 'Mixed'
        END AS performance_status
    FROM team_season_stats curr
    JOIN team_season_stats prev 
        ON curr.Team_Id = prev.Team_Id 
        AND curr.Season_Year = prev.Season_Year + 1
    JOIN team t ON curr.Team_Id = t.Team_Id)
SELECT * FROM yearly_comparison
ORDER BY Team_Name, Season_Year;

-- 12.Can you derive more KPIs for the team strategy?
WITH team_performance AS (
    SELECT   
        m.Season_Id,s.Season_Year,t.Team_Id,t.Team_Name,
        COUNT(DISTINCT m.Match_Id) AS matches_played,
        COUNT(b.Ball_Id) AS total_balls,
        SUM(b.Runs_Scored) AS total_runs,
        COUNT(w.Player_Out) AS total_wickets,
        -- Boundary, Dot balls
        SUM(CASE WHEN b.Runs_Scored = 4 THEN 1 ELSE 0 END) AS total_fours,
        SUM(CASE WHEN b.Runs_Scored = 6 THEN 1 ELSE 0 END) AS total_sixes,
        SUM(CASE WHEN b.Runs_Scored = 0 THEN 1 ELSE 0 END) AS dot_balls,
        -- Phase-specific runs
        SUM(CASE WHEN b.Over_Id < 7 THEN b.Runs_Scored ELSE 0 END) AS powerplay_runs,
        SUM(CASE WHEN b.Over_Id BETWEEN 7 AND 15 THEN b.Runs_Scored ELSE 0 END) AS middle_overs_runs,
        SUM(CASE WHEN b.Over_Id >= 16 THEN b.Runs_Scored ELSE 0 END) AS death_over_runs,
        -- Wins
        COUNT(DISTINCT CASE WHEN m.Match_Winner = t.Team_Id THEN m.Match_Id END) AS matches_won
    FROM team t
    JOIN matches m ON t.Team_Id IN (m.Team_1, m.Team_2)
    JOIN season s ON m.Season_Id = s.Season_Id
    LEFT JOIN ball_by_ball b ON b.Match_Id = m.Match_Id AND b.Team_Batting = t.Team_Id
    LEFT JOIN wicket_taken w ON b.Match_Id = w.Match_Id 
	GROUP BY m.Season_Id, s.Season_Year, t.Team_Id, t.Team_Name),
performance_comparison AS (
    SELECT
        Season_Year,Team_Name,matches_played,total_runs,total_wickets,total_balls,total_fours,
        total_sixes,dot_balls,powerplay_runs,middle_overs_runs,death_over_runs,matches_won,
        ROUND((total_runs * 6.0) / NULLIF(total_balls, 0), 2) AS economy_rate,
        ROUND(total_runs * 100.0 / NULLIF(total_balls, 0), 2) AS strike_rate,
        ROUND(total_runs * 1.0 / NULLIF(matches_played, 0), 2) AS avg_runs_per_match,
        ROUND(total_wickets * 1.0 / NULLIF(matches_played, 0), 2) AS avg_wickets_per_match,
        ROUND(dot_balls * 100.0 / NULLIF(total_balls, 0), 2) AS dot_ball_percentage,
        ROUND((total_fours + total_sixes) * 100.0 / NULLIF(total_balls, 0), 2) AS boundary_percentage,
        LAG(total_runs) OVER (PARTITION BY Team_Name ORDER BY Season_Year) AS prev_year_runs,
        LAG(total_wickets) OVER (PARTITION BY Team_Name ORDER BY Season_Year) AS prev_year_wickets,
        LAG(ROUND(total_runs * 100.0 / NULLIF(total_balls, 0), 2)) OVER (PARTITION BY Team_Name ORDER BY Season_Year) AS prev_strike_rate
    FROM team_performance)
SELECT 
    Season_Year,Team_Name,matches_played,total_runs,total_wickets,avg_runs_per_match,avg_wickets_per_match,
    strike_rate,economy_rate,dot_ball_percentage,boundary_percentage,powerplay_runs,middle_overs_runs,
    death_over_runs,matches_won,prev_year_runs,prev_year_wickets,prev_strike_rate,
    CASE  
        WHEN total_runs > prev_year_runs AND total_wickets > prev_year_wickets AND strike_rate > prev_strike_rate THEN 'Significantly Better'
        WHEN total_runs > prev_year_runs AND total_wickets > prev_year_wickets THEN 'Better'
        WHEN total_runs < prev_year_runs AND total_wickets < prev_year_wickets AND strike_rate < prev_strike_rate THEN 'Significantly Worse'
        WHEN total_runs < prev_year_runs AND total_wickets < prev_year_wickets THEN 'Worse'
        WHEN strike_rate > prev_strike_rate THEN 'Improved Strike Rate'
        ELSE 'Mixed'
    END AS performance_status
FROM performance_comparison
WHERE prev_year_runs IS NOT NULL
ORDER BY Team_Name, Season_Year;

-- 13.Using SQL, write a query to find out the average wickets taken by each bowler in each venue. Also, rank the gender according to the average value.
WITH bowler_venue_stats AS (
    SELECT 
        pm.Player_Id,v.Venue_Name,
        COUNT(w.Player_Out) AS total_wickets,
        COUNT(DISTINCT m.Match_Id) AS matches_played
    FROM wicket_taken w
    JOIN matches m ON w.Match_Id = m.Match_Id
    JOIN venue v ON m.Venue_Id = v.Venue_Id
    JOIN player_match pm ON w.Match_Id = pm.Match_Id AND pm.Player_Id = w.Player_Out
    GROUP BY pm.Player_Id, v.Venue_Name),
average_wickets AS (
    SELECT 
        bvs.Player_Id,p.Player_Name,bvs.Venue_Name,
        ROUND(bvs.total_wickets * 1.0 / NULLIF(bvs.matches_played, 0), 2) AS avg_wickets
    FROM bowler_venue_stats bvs
    JOIN player p ON bvs.Player_Id = p.Player_Id)
SELECT *,
    RANK() OVER (PARTITION BY Venue_Name ORDER BY avg_wickets DESC) AS venue_rank
FROM average_wickets
ORDER BY Venue_Name, venue_rank;

-- 14.Which of the given players have consistently performed well in past seasons? (will you use any visualization to solve the problem)
SELECT 
    b.Striker AS Player_Id,p.Player_Name,
    MIN(player_runs) AS Min_Runs,
    MAX(player_runs) AS Max_Runs,
    ROUND(AVG(player_runs), 2) AS Avg_Runs
FROM (
    SELECT 
        Match_Id,Striker, 
        SUM(Runs_Scored) AS player_runs
    FROM ball_by_ball
    GROUP BY Match_Id, Striker) AS b
JOIN player p ON b.Striker = p.Player_Id
GROUP BY b.Striker, p.Player_Name
ORDER BY Avg_Runs DESC;

-- 15.Are there players whose performance is more suited to specific venues or conditions? (how would you present this using charts?) 
-- for Striker
SELECT 
    b.Striker AS Player_Id,
     p.Player_Name,
    v.Venue_Name,
    SUM(b.Runs_Scored) AS total_runs,
    COUNT(DISTINCT b.Match_Id) AS matches_played,
    ROUND(SUM(b.Runs_Scored) * 1.0 / COUNT(DISTINCT b.Match_Id), 2) AS avg_runs
FROM ball_by_ball b
JOIN matches m ON b.Match_Id = m.Match_Id
JOIN venue v ON m.Venue_Id = v.Venue_Id
JOIN player p ON b.Striker = p.Player_Id
GROUP BY b.Striker, p.Player_Name, v.Venue_Name
ORDER BY p.Player_Name, avg_runs DESC;

-- for bowler
SELECT 
    b.Bowler AS Player_Id,
    p.Player_Name,
    v.Venue_Name,
    COUNT(w.Player_Out) AS total_wickets,
    COUNT(DISTINCT b.Match_Id) AS matches_played,
    ROUND(COUNT(w.Player_Out) * 1.0 / COUNT(DISTINCT b.Match_Id), 2) AS avg_wickets
FROM ball_by_ball b
JOIN wicket_taken w ON b.Match_Id = w.Match_Id 
    AND b.Over_Id = w.Over_Id AND b.Ball_Id = w.Ball_Id AND b.Innings_No = w.Innings_No
JOIN matches m ON b.Match_Id = m.Match_Id
JOIN venue v ON m.Venue_Id = v.Venue_Id
JOIN player p ON b.Bowler = p.Player_Id
GROUP BY b.Bowler, p.Player_Name, v.Venue_Name
ORDER BY p.Player_Name, avg_wickets DESC;



