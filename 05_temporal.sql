SET NOCOUNT ON;
SELECT p.ProductID,p.Name INTO #M FROM Production.Product p WHERE p.MakeFlag=0 AND p.FinishedGoodsFlag=0 AND EXISTS(SELECT 1 FROM Purchasing.ProductVendor v WHERE v.ProductID=p.ProductID);
SELECT COUNT(*) AS PurchasedMaterials FROM #M;
SELECT w.WorkOrderID,w.ProductID AS AssemblyID,b.ComponentID,b.UnitMeasureCode,w.StartDate,w.OrderQty,b.PerAssemblyQty,b.BillOfMaterialsID,CAST(w.OrderQty AS decimal(18,4))*b.PerAssemblyQty AS Requirement INTO #R FROM Production.WorkOrder w JOIN Production.BillOfMaterials b ON b.ProductAssemblyID=w.ProductID AND w.StartDate>=b.StartDate AND (b.EndDate IS NULL OR w.StartDate<=b.EndDate) JOIN #M m ON m.ProductID=b.ComponentID;
CREATE INDEX IX_R ON #R(ComponentID,WorkOrderID) INCLUDE (UnitMeasureCode);
SELECT COUNT(*) AS JoinedRows,COUNT(DISTINCT ComponentID) AS CoveredMaterials,MIN(StartDate) AS MinDate,MAX(StartDate) AS MaxDate,COUNT(DISTINCT CAST(StartDate AS date)) AS ActiveDays FROM #R;
SELECT COUNT(*) AS DuplicateWOComponentGroups FROM (SELECT WorkOrderID,ComponentID FROM #R GROUP BY WorkOrderID,ComponentID HAVING COUNT(*)>1)x;
SELECT r.UnitMeasureCode AS BOMUnit,v.UnitMeasureCode AS PurchaseUnit,COUNT(DISTINCT r.ComponentID) AS Materials,COUNT(*) AS JoinedRows FROM (SELECT DISTINCT ComponentID,UnitMeasureCode FROM #R)r JOIN (SELECT DISTINCT ProductID,UnitMeasureCode FROM Purchasing.ProductVendor)v ON v.ProductID=r.ComponentID GROUP BY r.UnitMeasureCode,v.UnitMeasureCode;
SELECT r.ComponentID INTO #E FROM (SELECT DISTINCT ComponentID,UnitMeasureCode FROM #R) r JOIN Purchasing.ProductVendor v ON v.ProductID=r.ComponentID GROUP BY r.ComponentID HAVING SUM(CASE WHEN r.UnitMeasureCode<>v.UnitMeasureCode THEN 1 ELSE 0 END)=0;
SELECT COUNT(*) AS UnitCompatibleMaterials FROM #E;
DECLARE @lo date=(SELECT MIN(StartDate) FROM Production.WorkOrder), @hi date=(SELECT MAX(StartDate) FROM Production.WorkOrder);
;WITH d AS (SELECT @lo AS dt UNION ALL SELECT DATEADD(day,1,dt) FROM d WHERE dt<@hi)
SELECT dt INTO #D FROM d OPTION(MAXRECURSION 0);
SELECT d.dt AS NoWorkOrderDate FROM #D d WHERE NOT EXISTS(SELECT 1 FROM Production.WorkOrder w WHERE w.StartDate=d.dt);
SELECT e.ComponentID,m.Name,COUNT(DISTINCT CASE WHEN r.StartDate>='20220701' AND r.StartDate<'20250601' THEN YEAR(r.StartDate)*12+MONTH(r.StartDate) END) AS ActiveFullMonths,35-COUNT(DISTINCT CASE WHEN r.StartDate>='20220701' AND r.StartDate<'20250601' THEN YEAR(r.StartDate)*12+MONTH(r.StartDate) END) AS NoRowFullMonths, MIN(r.StartDate) AS FirstDate,MAX(r.StartDate) AS LastDate FROM #E e JOIN #M m ON m.ProductID=e.ComponentID JOIN #R r ON r.ComponentID=e.ComponentID GROUP BY e.ComponentID,m.Name ORDER BY e.ComponentID;
SELECT YEAR(r.StartDate) AS Yr,MONTH(r.StartDate) AS Mo FROM #R r WHERE r.ComponentID=319 GROUP BY YEAR(r.StartDate),MONTH(r.StartDate) ORDER BY Yr,Mo;
SELECT MIN(dt) AS MinDate,MAX(dt) AS MaxDate,COUNT(*) AS CalendarDays,COUNT(DISTINCT DATEDIFF(day,'19000101',dt)/7) AS CalendarWeeks FROM #D;
SELECT e.ComponentID,MIN(r.StartDate) AS FirstDate,MAX(r.StartDate) AS LastDate,COUNT(DISTINCT CAST(r.StartDate AS date)) AS ActiveDays FROM #E e JOIN #R r ON r.ComponentID=e.ComponentID GROUP BY e.ComponentID;
