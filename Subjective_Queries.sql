use ipl;

-- 1.How does the toss decision affect the result of the match? (which visualizations could be used to present your answer better) And is the impact limited to only specific venues?
SELECT 
    v.Venue_Name,
    m.Toss_Decide,
    COUNT(*) AS Total_Matches,
    SUM(CASE WHEN m.Toss_Winner = m.Match_Winner THEN 1 ELSE 0 END) AS Toss_Win_Matches,
    ROUND(100.0 * SUM(CASE WHEN m.Toss_Winner = m.Match_Winner THEN 1 ELSE 0 END) / COUNT(*),2) AS Toss_Win_Percentage
FROM matches m
JOIN venue v ON m.Venue_Id = v.Venue_Id
GROUP BY v.Venue_Name, m.Toss_Decide
ORDER BY v.Venue_Name, Toss_Win_Percentage DESC;

-- 2.Suggest some of the players who would be best fit for the team.
SELECT 
    p.Player_Name,
    SUM(bbb.Runs_Scored) AS Total_Runs,
    COUNT(*) AS Balls_Faced,
    COUNT(DISTINCT CASE WHEN wt.Player_Out = p.Player_Id THEN bbb.Match_Id || '-' || bbb.Over_Id || '-' || bbb.Ball_Id END) AS Times_Out,
    ROUND(SUM(bbb.Runs_Scored) * 1.0 / NULLIF(COUNT(DISTINCT CASE WHEN wt.Player_Out = p.Player_Id THEN bbb.Match_Id || '-' || bbb.Over_Id || bbb.Ball_Id END), 0),
    2) AS Batting_Average,
    ROUND(SUM(bbb.Runs_Scored) * 100.0 / COUNT(*), 2) AS Strike_Rate
FROM ball_by_ball bbb
JOIN player p ON bbb.Striker = p.Player_Id
LEFT JOIN wicket_taken wt ON 
    bbb.Match_Id = wt.Match_Id AND 
    bbb.Over_Id = wt.Over_Id AND 
    bbb.Ball_Id = wt.Ball_Id AND 
    bbb.Innings_No = wt.Innings_No
GROUP BY p.Player_Name
HAVING COUNT(*) >= 100 
ORDER BY Total_Runs DESC, Strike_Rate DESC
LIMIT 20;

-- 4.Which players offer versatility in their skills and can contribute effectively with both bat and ball?
WITH activity AS (
  SELECT
    p.Player_Id,
    p.Player_Name,
    SUM(CASE WHEN b.Striker = p.Player_Id THEN b.Runs_Scored ELSE 0 END) AS total_runs,
    COUNT(CASE WHEN b.Striker = p.Player_Id AND w.Player_Out = p.Player_Id THEN 1 END) AS times_out,
    COUNT(DISTINCT CASE WHEN b.Striker = p.Player_Id THEN m.Match_Id END) AS bat_innings,
    COUNT(CASE WHEN b.Bowler = p.Player_Id AND w.Player_Out = p.Player_Id THEN 1 END) AS wickets_taken,
    SUM(CASE WHEN b.Bowler = p.Player_Id THEN b.Runs_Scored ELSE 0 END) AS runs_conceded,
    COUNT(DISTINCT CASE WHEN b.Bowler = p.Player_Id THEN m.Match_Id END) AS bowl_innings
  FROM player p
  LEFT JOIN ball_by_ball b
    ON p.Player_Id IN (b.Striker, b.Bowler)
  LEFT JOIN wicket_taken w
    ON  b.Match_Id   = w.Match_Id
  JOIN matches m
    ON b.Match_Id = m.Match_Id
  GROUP BY p.Player_Id, p.Player_Name)
  
SELECT
  Player_Name,
  bat_innings AS Matches_Played,
  ROUND(total_runs * 1.0 / NULLIF(times_out, 0), 2) AS Batting_Average,
  wickets_taken AS Wickets_Taken,
  ROUND(runs_conceded * 1.0 / NULLIF(wickets_taken, 0), 2) AS Bowling_Average,
  ROUND(
    (total_runs * 1.0 / NULLIF(times_out, 0))
    + (wickets_taken * 20.0)
    - (runs_conceded * 1.0 / NULLIF(wickets_taken, 0)),2) AS All_Rounder_Score
FROM activity
WHERE
  bat_innings >= 20
  AND wickets_taken >= 10
  AND (total_runs * 1.0 / NULLIF(times_out, 0)) > 20
ORDER BY All_Rounder_Score DESC
LIMIT 20;

-- 5.Are there players whose presence positively influences the morale and performance of the team? 
WITH player_team_wins AS (
  SELECT 
    pm.Player_Id,
    pm.Team_Id,
    COUNT(*) AS Matches_Played,
    SUM(CASE WHEN m.Match_Winner = pm.Team_Id THEN 1 ELSE 0 END) AS Wins_With_Player
  FROM player_match pm
  JOIN matches m ON pm.Match_Id = m.Match_Id
  GROUP BY pm.Player_Id, pm.Team_Id),
player_win_rate AS (
  SELECT 
    ptw.Player_Id,
    p.Player_Name,
    ptw.Team_Id,
    ptw.Matches_Played,
    ptw.Wins_With_Player,
    ROUND(CAST(ptw.Wins_With_Player AS FLOAT) / ptw.Matches_Played, 3) AS Win_Rate
  FROM player_team_wins ptw
  JOIN player p ON p.Player_Id = ptw.Player_Id)
SELECT *
FROM player_win_rate
ORDER BY Win_Rate DESC
LIMIT 20;  

-- 7.What do you think could be the factors contributing to the high-scoring matches and the impact on viewership and team strategies
WITH run_details AS (
    SELECT 
        b.Match_Id,b.Team_Batting,
        SUM(b.Runs_Scored) + COALESCE(SUM(er.Extra_Runs), 0) AS Total_Runs,
        SUM(CASE WHEN b.Over_Id < 7 THEN b.Runs_Scored ELSE 0 END) AS Powerplay_Runs,
        SUM(CASE WHEN b.Over_Id >= 16 THEN b.Runs_Scored ELSE 0 END) AS Death_Over_Runs
    FROM ball_by_ball b
    LEFT JOIN extra_runs er ON 
        b.Match_Id = er.Match_Id 
	GROUP BY b.Match_Id, b.Team_Batting),
high_scoring_matches AS (
    SELECT 
        r.Match_Id,r.Team_Batting,r.Total_Runs,r.Powerplay_Runs,r.Death_Over_Runs,
        m.Season_Id,m.Venue_Id,m.Match_Winner,m.Win_Type,m.Outcome_type
    FROM run_details r
    JOIN matches m ON r.Match_Id = m.Match_Id),
venue_info AS (
    SELECT 
        v.Venue_Id,v.Venue_Name,c.City_Name,co.Country_Name
    FROM venue v
    JOIN city c ON v.City_Id = c.City_Id
    JOIN country co ON c.Country_Id = co.Country_Id),
final_output AS (
    SELECT 
        hsm.Match_Id,t.Team_Name AS Batting_Team,vi.Venue_Name,
        vi.City_Name,vi.Country_Name,hsm.Total_Runs,
        hsm.Powerplay_Runs,hsm.Death_Over_Runs,s.Season_Year,
        wb.Win_Type AS Type_of_Win,o.Outcome_Type
    FROM high_scoring_matches hsm
    JOIN team t ON hsm.Team_Batting = t.Team_Id
    JOIN venue_info vi ON hsm.Venue_Id = vi.Venue_Id
    JOIN season s ON hsm.Season_Id = s.Season_Id
    JOIN win_by wb ON hsm.Win_Type = wb.Win_Id
    JOIN outcome o ON hsm.Outcome_type = o.Outcome_Id)
SELECT *
FROM final_output
ORDER BY Total_Runs DESC, Death_Over_Runs DESC
LIMIT 20;


-- 8.Analyze the impact of home-ground advantage on team performance and identify strategies to maximize this advantage for RCB.
WITH team_performance AS (
    SELECT 
        t.Team_Name,v.Venue_Name,m.Match_Id,
        SUM(b.Runs_Scored) AS Total_Runs,
        COUNT(w.Player_Out) AS Wickets_Taken,
        SUM(CASE WHEN b.Over_Id >= 16 THEN b.Runs_Scored ELSE 0 END) * 6.0 / COUNT(CASE WHEN b.Over_Id >= 16 THEN 1 END) AS Death_Over_Economy,
        CASE WHEN v.Venue_Name = 'M Chinnaswamy Stadium' THEN 'Home' ELSE 'Away' END AS Ground_Type,
        CASE WHEN m.Outcome_type = 2 THEN 1 ELSE 0 END AS Win
    FROM matches m
    JOIN player_match pm ON m.Match_Id = pm.Match_Id
    JOIN team t ON pm.Team_Id = t.Team_Id
    JOIN ball_by_ball b ON m.Match_Id = b.Match_Id
    LEFT JOIN wicket_taken w ON b.Match_Id = w.Match_Id AND b.Over_Id = w.Over_Id AND b.Ball_Id = w.Ball_Id
    JOIN venue v ON m.Venue_Id = v.Venue_Id
    WHERE t.Team_Name = 'Royal Challengers Bangalore'
    GROUP BY t.Team_Name, v.Venue_Name, m.Match_Id),
team_home_away_stats AS (
    SELECT 
        Ground_Type,
        COUNT(DISTINCT Match_Id) AS Matches_Played,
        SUM(Win) AS Wins,
        ROUND(SUM(Win) * 100.0 / COUNT(DISTINCT Match_Id), 2) AS Win_Percentage,
        AVG(Total_Runs) AS Avg_Runs_Scored,
        AVG(Wickets_Taken) AS Avg_Wickets_Taken,
        ROUND(AVG(Death_Over_Economy), 2) AS Avg_Death_Over_Economy
    FROM team_performance
    GROUP BY Ground_Type)
SELECT 
    Ground_Type AS Venue_Type,Matches_Played,Wins,Win_Percentage,
    Avg_Runs_Scored,Avg_Wickets_Taken,Avg_Death_Over_Economy
FROM team_home_away_stats;

-- 9.Come up with a visual and analytical analysis of the RCB's past season's performance and potential reasons for them not winning a trophy.
WITH rcb_performance AS (
    SELECT 
        m.Match_Id,m.Season_Id,m.Match_Winner,
        SUM(CASE WHEN (m.Team_1 = 2 OR m.Team_2 = 2) AND b.Striker = 2 THEN b.Runs_Scored ELSE 0 END) AS Runs_Scored,
        SUM(CASE WHEN (m.Team_1 = 2 OR m.Team_2 = 2) AND b.Striker != 2 THEN b.Runs_Scored ELSE 0 END) AS Runs_Conceded
    FROM matches m
    JOIN ball_by_ball b ON m.Match_Id = b.Match_Id
    WHERE m.Team_1 = 2 OR m.Team_2 = 2
    GROUP BY m.Match_Id, m.Season_Id, m.Match_Winner)
SELECT
    Season_Id,
    COUNT(CASE WHEN Match_Winner = 2 THEN 1 END) AS Wins,
    COUNT(CASE WHEN Match_Winner != 2 AND Match_Winner IS NOT NULL THEN 1 END) AS Losses,
    ROUND(AVG(Runs_Scored), 2) AS Avg_Runs_Scored,
    ROUND(AVG(Runs_Conceded), 2) AS Avg_Runs_Conceded
FROM rcb_performance
GROUP BY Season_Id
ORDER BY Season_Id;

-- 11.In the "Match" table, some entries in the "Opponent_Team" column are incorrectly spelled as "Delhi_Capitals" instead of "Delhi_Daredevils". Write an SQL query to replace all occurrences of "Delhi_Capitals" with "Delhi_Daredevils".

UPDATE team
SET Team_Name = 'Delhi Daredevils'
WHERE Team_Name = 'Delhi Capitals';

SELECT m.*
FROM matches m
JOIN team t ON m.Team_2 = t.Team_Id
WHERE t.Team_Name = 'Delhi Daredevils';
