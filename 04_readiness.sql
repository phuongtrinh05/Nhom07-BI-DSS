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
SELECT YEAR(StartDate) AS Year,MONTH(StartDate) AS Month,COUNT(*) AS WorkOrders,COUNT(DISTINCT CAST(StartDate AS date)) AS ActiveDays FROM Production.WorkOrder GROUP BY YEAR(StartDate),MONTH(StartDate) ORDER BY Year,Month;
SELECT r.ComponentID,m.Name,MIN(r.StartDate) AS FirstDate,MAX(r.StartDate) AS LastDate,COUNT(DISTINCT CAST(r.StartDate AS date)) AS ActiveDays,COUNT(DISTINCT DATEDIFF(day,'19000101',r.StartDate)/7) AS ActiveWeeks,COUNT(DISTINCT YEAR(r.StartDate)*12+MONTH(r.StartDate)) AS ActiveMonths,SUM(r.Requirement) AS TotalRequirement,CASE WHEN e.ComponentID IS NULL THEN 0 ELSE 1 END AS UnitCompatible FROM #R r JOIN #M m ON m.ProductID=r.ComponentID LEFT JOIN #E e ON e.ComponentID=r.ComponentID GROUP BY r.ComponentID,m.Name,e.ComponentID ORDER BY UnitCompatible DESC,r.ComponentID;
SELECT COUNT(*) AS NullOrInvalidWorkOrders FROM Production.WorkOrder WHERE StartDate IS NULL OR OrderQty<=0;
SELECT COUNT(*) AS InvalidBOMQty FROM Production.BillOfMaterials WHERE PerAssemblyQty<=0;
SELECT COUNT(*) AS WTransactionsMatchingOutput, SUM(CASE WHEN t.ProductID=w.ProductID AND t.Quantity=w.StockedQty THEN 1 ELSE 0 END) AS SameProductAndStockedQty FROM (SELECT * FROM Production.TransactionHistory WHERE TransactionType='W' UNION ALL SELECT * FROM Production.TransactionHistoryArchive WHERE TransactionType='W')t JOIN Production.WorkOrder w ON t.ReferenceOrderID=w.WorkOrderID;
SELECT TOP(5) r.WorkOrderID,r.AssemblyID,r.ComponentID,r.StartDate,r.OrderQty,r.PerAssemblyQty,r.UnitMeasureCode,r.Requirement FROM #R r JOIN #E e ON e.ComponentID=r.ComponentID ORDER BY r.StartDate,r.WorkOrderID,r.ComponentID;


