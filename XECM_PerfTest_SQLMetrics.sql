--Get Batch Requests/Sec 
DECLARE @v1 BIGINT, @delay SMALLINT = 2, @time DATETIME, @batchrequest INT;
SELECT @time = DATEADD(SECOND, @delay, '00:00:00');
SELECT @v1 = cntr_value FROM master.sys.dm_os_performance_counters WHERE counter_name = 'Batch Requests/sec';
WAITFOR DELAY @time;
SELECT @batchrequest=(cntr_value - @v1)/@delay FROM master.sys.dm_os_performance_counters WHERE counter_name='Batch Requests/sec'

--Get remaining counter values
SELECT CASE @@SERVERNAME
			  WHEN 'PSQLXECM05\XECM05' THEN 'XECM - ContenetDB'
			  WHEN 'PSQLXECM06\XECM06' THEN 'XECM - Stream Serve 1 & Archive DB'
			  WHEN 'PSQLXECM08\XECM08' THEN 'XECM - Stream Serve 2'
              ELSE ''
          END AS [Application Name],
         CASE 
              WHEN T2.System_Idle_CPU>50 THEN 'Green' 
              WHEN T2.System_Idle_CPU>20 AND T2.System_Idle_CPU <50 THEN 'Yellow' 
              ELSE 'Red'
         END AS [Status],         
       T2.System_Idle_CPU,T2.sql_cpu_utilization,T2.non_sql_cpu_utilization,
       T1.[Memory allocated-GB], T1.[Memory Used - GB],T1.BCHR,T1.PLE_minutes,
       T1.[Active Requests],
          T1.[Blocked Requests],
          T1.Sessions,
		  @batchrequest [BatchRequest/Sec],
          T2.record_time [CPU_Record_Time] 
 FROM
       (
              SELECT @@SERVERNAME AS ServerName,
			  (SELECT CONVERT(decimal(10,2),(cntr_value/1048576.0))FROM sys.dm_os_performance_counters WHERE counter_name = 'Total Server Memory (KB)')AS [Memory Used - GB],
              (SELECT CONVERT(decimal(10,2),(cntr_value/1048576.0))FROM sys.dm_os_performance_counters WHERE counter_name = 'Target Server Memory (KB)') AS [Memory allocated-GB],
              (SELECT (SELECT (cntr_value*100))/(SELECT (cntr_value) FROM sys.dm_os_performance_counters WHERE counter_name='Buffer cache hit ratio base')FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio')AS [BCHR],
              (SELECT cntr_value/60 FROM sys.dm_os_performance_counters WHERE counter_name ='Page life expectancy' AND object_name LIKE '%Buffer Manager%') AS [PLE_minutes],
              (SELECT COUNT(*) FROM sys.dm_exec_requests req JOIN sys.dm_exec_sessions sess ON req.session_id = sess.session_id WHERE sess.is_user_process = 1 AND sess.session_id <> @@SPID) AS [Active Requests],
              (SELECT COUNT(*) FROM sys.dm_exec_requests req WHERE req.blocking_session_id > 0) AS [Blocked Requests],
              (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process=1) AS [Sessions]
       ) T1
    INNER JOIN 
       (
              SELECT TOP 1 @@SERVERNAME AS [ServerName],MAX(sql_cpu_utilization)AS[sql_cpu_utilization],MAX(record_time)AS[record_time],MAX(System_Idle_Percent)AS [System_Idle_CPU],
                                  (100- MAX(System_Idle_Percent)-MAX(sql_cpu_utilization))AS [non_sql_cpu_utilization] 
              FROM
                    (SELECT TOP 5 CAST(record AS XML).value('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS sql_cpu_utilization ,
                     CAST(record AS XML).value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS [System_Idle_Percent]
                     ,dateadd (ms, r.[timestamp] - sys.ms_ticks, getdate()) as record_time
                     FROM sys.dm_os_ring_buffers r
                     CROSS JOIN sys.dm_os_sys_info sys  
                     WHERE ring_buffer_type = 'RING_BUFFER_SCHEDULER_MONITOR'
                     ORDER BY record_time DESC)a
              GROUP BY System_Idle_Percent
              ORDER BY System_Idle_Percent
       )T2
       ON T1.ServerName=T2.ServerName
ORDER BY [Application Name]


