-- Maze Generator Application

--[[ Maze type, I decided to make the maze OOP as I believed it would have been easier to treat it as an object and add functionality onto it,
It seems as I was right later on, I have only used OOP twice so I really thought it was gonna be useful. It has all the Info I think would be
needed outside of its scope, a.k.a used everyone in the script with the self : Maze being passed. ]]
export type Maze = typeof(setmetatable({} :: {
	OriginPosition : Vector3, -- The Position the maze should be created from or the first cell(0,0) should be placed.
	GridSize : number, -- Grid Dimensions like 10x10, 20x20, Maze is always a Square so it is just a number.
	MazeFolder : Folder?, -- A reference to the folder that holds all the Cells in the Maze
	Cells : {string : Cell}?, -- A table that holds all the Cells in the Maze and their information like Direction and Whether it is Visited
	OriginCell : string?, -- Fun fact it was previously OriginNode, as I was using the reference of the OriginShift video while creating that algorithm
	NonVisitedCells : {string}? -- I decided to make it a part of the object so I didn't need to pass over the table in a function, so if a Cell is not inside Ik it is visited, if it is ik it isn't visited
}, MazeGenerator))

type Cell = {Direction : string, Visited : boolean} -- I needed Direction value so that when updating the maze it can adjust the celss depending on its direction.
type AStarCellInfo = { Fcost : number?, Gcost : number?, Hcost : number?, Origin : string?, PathDistance : number?, Closed : boolean, Start : boolean? } -- According to the A* algorithm, I only needed those values, tbh idk the point of pathdistance.

local MazeGenerator = {}
MazeGenerator.__index = MazeGenerator -- OOP

local CellSize = 8 -- I plan to add the ability to change the actual size of the maze, rn all cells are 8x8, don't mistaken for the Grid
local Cell = game:GetService("ReplicatedStorage"):WaitForChild("Cell") -- Reference to the Cell Instance

local FloorColor = Color3.new(1, 1, 1) -- Default Cell Floor Colour, incase I wanted to change it for whatsoever reason
local WallColor = Color3.fromHex("#1b2a35") -- Defauly Wall Colour, vice versa

local function AbbreviateDir(Direction : string) -- I earlier only used "S","N","W","E" to show direction then randomly one of my functions uses the full name so I had to add a way to convert it back.
	return string.split(Direction, "")[1] -- splits string so West, {"W", "E", "S", "T"} then return the first Letter "W"
end

local function UnAbbreviateDir(Direction : string) -- Opposite of the top,
	local Dirs = {["N"] = "North", ["W"] = "West", ["S"] = "South", ["E"] = "East"}
	return Dirs[Direction]
end

local function ChangeWallColor(Cell : Model, Color : Color3) -- A Simple function for changing a cell wall colour
	for _, Wall in Cell:GetChildren() do
		if Wall.Name ~= "Floor" or Wall.Name ~= "Middle" then
			Wall.Color = Color
		end
	end
end

local function ChangeCellFloorColor(self : Maze, Cell : string, Color : Color3) -- A Simple function that changes the floor colour, why did I call it color I blame roblox and their american naming
	self.MazeFolder[Cell].Middle.Color = Color
end

local function ChangeToOrigin(Cell : Model) -- It Changed a cell to an OriginNode, was used in the past as a way of resseting the Maze or showing a cell as without direction, but I don't use it again, tho maybe later
	for _, Wall : BasePart in Cell:GetChildren() do
		if Wall.Name ~= "Floor" or Wall.Name ~= "Middle" then
			Wall.Transparency = 0
			Wall.CanCollide = true
		end
	end
	Cell.Middle.Color = Color3.new(1, 0, 0)
end

local function CoordToTable(Coord : string) : {x : number, z : number} -- Turns The Coords I name cells "0,1" to a table {x = 0, z = 1}
	local Split = string.split(Coord, ",")
	local CoordTable = {x = Split[1], z = Split[2]}
	return CoordTable
end --  I just realised I should have converted tonumber(), this why --!strict is useful, this caused me errors later on cause it was a string

local function GetNeighbourCells(self : Maze, Coord : string) -- Gets all the reference of a Cell's neighbour in the maze folder that holds all physical cells.
	local NeighbourCells = {}

	local MazeFolder = self.MazeFolder
	local CoordTable = CoordToTable(Coord)

	NeighbourCells.North = MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z - 1)) -- The Z-Axis is Vertical from 0 - Gridsize, so z-axis - 1 would be above the Cell being North.
	NeighbourCells.East = MazeFolder:FindFirstChild((CoordTable.x + 1)..","..CoordTable.z) -- The X-Axis is Horizontal from 0 - Gridsize, so x-axis + 1 would be "infront" of the cell to the East.
	NeighbourCells.South = MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z + 1))
	NeighbourCells.West = MazeFolder:FindFirstChild((CoordTable.x - 1)..","..CoordTable.z)

	return NeighbourCells
end

local function GetNeighbourCoords(self : Maze, Coord : string) -- Gets all the neighbour Coords, and set nil to the impossible ones
	local NeighbourCells = {}

	local MazeFolder = self.MazeFolder
	local CoordTable = CoordToTable(Coord)

	NeighbourCells.North = CoordTable.x..","..(CoordTable.z - 1)
	NeighbourCells.East = (CoordTable.x + 1)..","..CoordTable.z
	NeighbourCells.South = CoordTable.x..","..(CoordTable.z + 1)
	NeighbourCells.West = (CoordTable.x - 1)..","..CoordTable.z

	if CoordTable.z - 1 < 0 then NeighbourCells.North = nil end -- Can't be less than zero so it doesn't exist
	if CoordTable.z + 1 > self.GridSize then NeighbourCells.South = nil end -- Can't be more than the Gridsize do it doesn't exist
	if CoordTable.x - 1 < 0 then NeighbourCells.West = nil end 
	if CoordTable.x + 1 > self.GridSize then NeighbourCells.East = nil end

	return NeighbourCells
end

--[[ So to visual represent they maze, I save the maze state in a table using a Direction variable to show which direction it opens too, then I loop through all the cells in the table and update their state
this ChangeCellDirection is responsible in making those pyhsical changes to cell like opening up walls]]--
local function ChangeCellDirection(self : Maze, Coord : string, Direction : string) 
	local Cell = self.MazeFolder:FindFirstChild(Coord)
	if Direction == "E" then
		Cell.East.Transparency = 1
		Cell.East.CanCollide = false
		local CoordTable = CoordToTable(Coord)	
		local NextCell = self.MazeFolder:FindFirstChild((CoordTable.x + 1)..","..CoordTable.z) -- So earlier on met a problem where they wall will still be their realised that I have to also remove the neighbour opposite walls
		if not NextCell then print(CoordTable) end
		NextCell.West.Transparency = 1 -- Opposite of East being West
		NextCell.West.CanCollide = false
	elseif Direction == "W" then
		Cell.West.Transparency = 1
		Cell.West.CanCollide = false
		local CoordTable = CoordToTable(Coord)
		local NextCell = self.MazeFolder:FindFirstChild((CoordTable.x - 1)..","..CoordTable.z)
		if not NextCell then print(CoordTable) end
		NextCell.East.Transparency = 1
		NextCell.East.CanCollide = false
	elseif Direction == "S" then
		Cell.South.Transparency = 1
		Cell.South.CanCollide = false
		local CoordTable = CoordToTable(Coord)	
		local NextCell = self.MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z + 1))
		if not NextCell then print(CoordTable) end
		NextCell.North.Transparency = 1
		NextCell.North.CanCollide = false
	elseif Direction == "N" then
		Cell.North.Transparency = 1
		Cell.North.CanCollide = false
		local CoordTable = CoordToTable(Coord)
		local NextCell = self.MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z - 1))
		if not NextCell then print(CoordTable) end
		NextCell.South.Transparency = 1
		NextCell.South.CanCollide = false
	elseif Direction == "I" then -- Later on I added a direction called "I" meaning Ignore as it used to just set a directionless cell to origin even tho it wasn't meant to, which didn't work for other algorithms that didin't have a default direction like origin shift
		return
	else
		ChangeToOrigin(Cell)
	end
end

local function UpdateCell(self : Maze, Coord : string, Direction : string) -- Deals with updating the cell and neighbour cells
	local Cell = self.MazeFolder:FindFirstChild(Coord)
	local NeighbourCells = GetNeighbourCells(self, Coord)
	ChangeCellDirection(self, Coord, Direction)

	if NeighbourCells.North and self.Cells[NeighbourCells.North.Name].Direction == "S" then ChangeCellDirection(self, Coord, "N") end -- It updates the neighbour cells in relation to the cell, tbh this was only useful for origin shift.
	if NeighbourCells.East and self.Cells[NeighbourCells.East.Name].Direction == "W" then ChangeCellDirection(self, Coord, "E")  end
	if NeighbourCells.West and self.Cells[NeighbourCells.West.Name].Direction == "E" then ChangeCellDirection(self, Coord, "W") end
	if NeighbourCells.South and self.Cells[NeighbourCells.South.Name].Direction == "N" then ChangeCellDirection(self, Coord, "S") end

end

local function UpdateMazeWithCells(self : Maze, Cells : {string : Cell}) -- Loop that updates the maze
	local MazeFolder = self.MazeFolder

	for Coord, Cell in Cells do
		UpdateCell(self, Coord, Cell.Direction)
	end
end

local function RandomPossibleDirection(self : Maze, Coord : string) -- Gets a random possible direction, so any direction that isn't out of bounds.
	local PossibleNeighbours = {}

	local CoordTable = CoordToTable(Coord)

	if self.MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z - 1)) then table.insert(PossibleNeighbours, "N") end -- adds to a table
	if self.MazeFolder:FindFirstChild((CoordTable.x + 1)..","..CoordTable.z) then table.insert(PossibleNeighbours, "E") end
	if self.MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z + 1)) then table.insert(PossibleNeighbours, "S") end
	if self.MazeFolder:FindFirstChild((CoordTable.x - 1)..","..CoordTable.z) then table.insert(PossibleNeighbours, "W") end

	local RandomDirection = PossibleNeighbours[math.random(1, table.maxn(PossibleNeighbours))] -- get a random number between 1 and the amount of items in the table, then uses that as an index.

	return RandomDirection
end

local function RandomPossibleNotVisitedDirection(self : Maze, Coord : string) -- Gets a RandomPossible Direction, but filters out the ones that are already visited.
	local PossibleNeighbours = {}

	local CoordTable = CoordToTable(Coord)

	--[[Checks whether it is in NonvisitedCells table and if so insert, if not then skip. I could have also used self.Nodes[CoordTable.x..","..(CoordTable.z - 1)].Visited instead tbh that would be faster instead
	of searching through a table, promise I would change it]]-- 
	if self.MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z - 1)) and table.find(self.NonVisitedCells, CoordTable.x..","..(CoordTable.z - 1)) then table.insert(PossibleNeighbours, "N") end
	if self.MazeFolder:FindFirstChild((CoordTable.x + 1)..","..CoordTable.z) and table.find(self.NonVisitedCells, (CoordTable.x + 1)..","..CoordTable.z) then table.insert(PossibleNeighbours, "E") end
	if self.MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z + 1)) and table.find(self.NonVisitedCells, CoordTable.x..","..(CoordTable.z + 1)) then table.insert(PossibleNeighbours, "S") end
	if self.MazeFolder:FindFirstChild((CoordTable.x - 1)..","..CoordTable.z) and table.find(self.NonVisitedCells, (CoordTable.x - 1)..","..CoordTable.z) then table.insert(PossibleNeighbours, "W") end

	local Size = table.maxn(PossibleNeighbours)
	if Size < 1 then return end -- Possible for all surrounding neighbours to be visited, so it returns nil this is used in the wilson algorithm I believe.

	local RandomDirection = PossibleNeighbours[math.random(1, Size)]

	return RandomDirection
end

local function GetCellFromDirection(self : Maze, Coord : string, Direction : string) -- Returns the Neighbour Coords with their direction as indexes in a table.
	local NeighbourCells = {}

	local CoordTable = CoordToTable(Coord)

	NeighbourCells.N = CoordTable.x..","..(CoordTable.z - 1)
	NeighbourCells.E = (CoordTable.x + 1)..","..CoordTable.z
	NeighbourCells.S = CoordTable.x..","..(CoordTable.z + 1)
	NeighbourCells.W = (CoordTable.x - 1)..","..CoordTable.z

	return NeighbourCells[Direction]
end

local function CoordToCell(self : Maze, Coord : string) -- Gets the physical Cell Model reference from a Coordinate ex. ("1,2")
	return self.MazeFolder:FindFirstChild(Coord)
end

--[=[
	Gets Coords of a Random Not Visited Cell
	was testing roblox function descirption
]=]
 --[[So code was much smaller than this but had a week long problem that stopped the wilson algorithm from working just to realise that this function was returning visited cells for some reason.
It used the roblox search feature, and tracked down every instance of adding to nonvisited table and still couldn't figure out why it would be in the nonvisited table and .Visited would be true.]]--
local function GetRandomNotVisitedCell(self : Maze)
	--[[Does a loop until it finds a nonvisited Cell that also has .visited as false and removed any that don't, fixing the problem, after doing this the wilson algorithm I gave up on actually worked, 
		they amount of time I spent debugging it was more than coding pratically all the algorithms]]--
	while #self.NonVisitedCells > 0 do
		local index = math.random(1, #self.NonVisitedCells)
		local cell = self.NonVisitedCells[index]

		if not self.Cells[cell].Visited then
			return cell -- , index if you also want the index
		else
			table.remove(self.NonVisitedCells, index)
		end
	end
	return
end

local function OppositeDirection(Direction : string)
	if Direction == "N" then return "S" end
	if Direction == "S" then return "N" end
	if Direction == "E" then return "W" end
	if Direction == "W" then return "E" end
end

local function SetCellToVisited(self : Maze, Cell : string)
	self.Cells[Cell].Visited = true
	table.remove(self.NonVisitedCells, table.find(self.NonVisitedCells, Cell))
	--self.MazeFolder:FindFirstChild(Cell).Middle.Transparency = 1 was used for visual feedback now I just use colors instead of empty
end

local function SetCellToNotVisited(self : Maze, Cell : string)
	self.Cells[Cell].Visited = false
	self.Cells[Cell].Direction = "O"
	table.insert(self.NonVisitedCells, Cell)
	ChangeCellFloorColor(self, Cell, Color3.new(1, 0, 0)) -- Visual feedback
	self.MazeFolder:FindFirstChild(Cell).Middle.Transparency = 0
end

local function EraseLoop(self : Maze, Cell : string, Walk : {string}) : {string?} -- For Wilson algorithm, it erases any loops.
	local Index = table.find(Walk, Cell)
	if not Index then return Walk end -- if for some reason, they cell which is supposed to be in the walk is not there then return walk without modifications.
	if #Walk == 1 then return Walk end -- If the cell is the only one in walk for some reason then just return the walk.

	for i = #Walk, #Walk - Index, -1 do -- This loop took a lot of testing, but it goes from the bottom of the table to right before the index, to delete all items after the index.
		if i < 2 then break end -- this is useless since I already check earlier on, hmmmm.
		SetCellToNotVisited(self, Walk[i])
		Walk[i] = nil
	end
	-- Practically if during the walk u find another cell that is already inside the walk then a loop has occured so just delete all cells after that cell to erase it.
	return Walk
end

local function GetDirectionBetweenCells(self : Maze, Cell1string : string, Cell2string : string) -- Gets Like what direction a cell is relative to the other cell.
	local Cell1 = CoordToTable(Cell1string)
	local Cell2 = CoordToTable(Cell2string)

	if tonumber(Cell2.x) > tonumber(Cell1.x) then return "E" end -- So if Cell2 has a greater x, it means that it is East of Cell1
	if tonumber(Cell2.x) < tonumber(Cell1.x) then return "W" end 
	if tonumber(Cell2.z) < tonumber(Cell1.z) then return "N" end -- So if Cell2 has a lesser z, it means that it is North of Cell1
	if tonumber(Cell2.z) > tonumber(Cell1.z) then return "S" end
end

function MazeGenerator.Create(OriginPosition : Vector3, GridSize : number) : Maze -- Init Function of the Maze, that creates the Maze object in OOP terms.
	local Maze : Maze = {OriginPosition = OriginPosition, GridSize = GridSize}

	local MazeFolder = game:GetService("Workspace").Maze -- Would add the ability to have more than one maze at a time.

	local OriginX = OriginPosition.X
	local OriginZ = OriginPosition.Z

	Cell.Floor.Color = FloorColor
	ChangeWallColor(Cell, WallColor)

	for x = 0, GridSize do -- Simple Grid Loop, for every z coord on the x axis it Clones the Prefab Maze Cell Model, then offset it according to the coords, names it the coords and parents to the MazeFolder.
		for z = 0, GridSize	do
			local NewCell : Model = Cell:Clone()
			local NewCFrame : CFrame = CFrame.new(OriginX + (CellSize * x), 5, OriginZ + (CellSize * z))
			NewCell:PivotTo(NewCFrame)
			NewCell.Name = x..","..z
			NewCell.Parent = MazeFolder
		end
	end

	Maze.MazeFolder = MazeFolder

	return setmetatable(Maze, MazeGenerator) -- OOP things
end

function MazeGenerator.Reset(self : Maze)
	for _, child in self.MazeFolder:GetChildren() do
		child:Destroy()
	end
	
	local NewMaze = MazeGenerator.Create(self.OriginPosition, self.GridSize)
	self = nil
	return NewMaze 
end

function MazeGenerator.Generate(Algorithm : string, Maze : Maze?)
	local NewMaze
	if not Maze then
		NewMaze = MazeGenerator.Create(Vector3.zero, 10)
	else
		NewMaze = MazeGenerator.Reset(Maze)
	end
	print(Algorithm)
	MazeGenerator[Algorithm](NewMaze)
	
	return NewMaze
end

function MazeGenerator.GetOriginPosition(self : Maze)
	return self.OriginPosition
end


function MazeGenerator.OriginShift(self : Maze, Iterations : number, UpdateInterval : number?) -- Origin Shift Algorithm, first one I coded.
	local Cells = {} :: {string : Cell} -- Table of all Cells including their direction and whether they are visited, which I would store in self later

	for x = 0, self.GridSize do -- Simple Grid Looping
		for z = 0, self.GridSize do
			if x ~= self.GridSize then
				Cells[x..","..z] = {Direction = "E", Visited = false}
			else
				Cells[x..","..z] = {Direction = "S", Visited = false}
			end
		end
	end
	-- Set all cells that aren't on the final row to E and they ones on the final row south, this makes it a perfect maze at default, as origin maze just keep it perfect in every iteration while changing.

	Cells[self.GridSize..","..self.GridSize].Direction = "O" -- Sets the Final cell as the origin Node.
	self.OriginCell = self.GridSize..","..self.GridSize -- kinda redundant but makes it easier.

	self.Cells = Cells -- store the cells to self.

	local CurrentIteration = 0 -- used in seperating visual updates later on. 
	if not Iterations then Iterations = self.GridSize^3 end
	if not UpdateInterval then UpdateInterval = 1 end

	UpdateMazeWithCells(self, Cells)

	while CurrentIteration < Iterations do		
		local NewDirection = RandomPossibleDirection(self, self.OriginCell)
		Cells[self.OriginCell].Direction = NewDirection -- We set the new direction
		ChangeCellDirection(self, self.OriginCell, NewDirection) -- Redundant, most likely because I hadn't code the visual updater by this time or I am stupid.
		self.MazeFolder[self.OriginCell].Middle.Transparency = 1 -- shows that it has been visited just for visuals

		local NewOriginCell = GetCellFromDirection(self, self.OriginCell, NewDirection)
		Cells[NewOriginCell].Direction = "O" -- It gets the new cell that is in that direction and it becomes the new origin node
		self.OriginCell = NewOriginCell 
		ChangeCellDirection(self, self.OriginCell, "O")

		CurrentIteration += 1
		if CurrentIteration % UpdateInterval == 0 then -- If CurrentIteration can be divided without remainder then it has passed the interval for it to be updated
			UpdateMazeWithCells(self, Cells)
			task.wait()
		end
	end

	UpdateMazeWithCells(self, Cells) -- final update incase update interval isn't a factor of iterations.
end

function MazeGenerator.AldrousBroder(self : Maze, UpdateInterval : number?)
	local Cells = {} :: {string : Cell}
	local NonVisitedCells = {} :: {string}

	for x = 0, self.GridSize do
		for z = 0, self.GridSize do
			Cells[x..","..z] = {Direction = "O", Visited = false}
			table.insert(NonVisitedCells, x..","..z)
		end
	end

	self.Cells = Cells
	self.NonVisitedCells = NonVisitedCells

	local CurrentIteration = 0
	UpdateMazeWithCells(self, Cells)
	local CurrentCell = GetRandomNotVisitedCell(self)
	if not UpdateInterval then UpdateInterval = 1 end

	while self.NonVisitedCells[1] do
		local RandomDirection = RandomPossibleDirection(self, CurrentCell)
		local NeighbourCell = GetCellFromDirection(self, CurrentCell, RandomDirection)

		if not self.Cells[NeighbourCell].Visited then
			self.Cells[NeighbourCell].Direction = OppositeDirection(RandomDirection)
			SetCellToVisited(self, NeighbourCell)
		end

		CurrentCell = NeighbourCell

		CurrentIteration += 1
		if CurrentIteration % 100 == UpdateInterval then
			UpdateMazeWithCells(self, Cells)
			task.wait()
		end
	end

	UpdateMazeWithCells(self, Cells)
end

function MazeGenerator.Wilson(self : Maze, UpdateInterval : number?)
	local Cells = {} :: {string : Cell}
	local NonVisitedCells = {} :: {string}

	for x = 0, self.GridSize do
		for z = 0, self.GridSize do
			Cells[x..","..z] = {Direction = "I", Visited = false}
			table.insert(NonVisitedCells, x..","..z)
		end
	end

	self.Cells = Cells
	self.NonVisitedCells = NonVisitedCells

	local CurrentIteration = 0
	if not UpdateInterval then UpdateInterval = 1 end

	UpdateMazeWithCells(self, Cells)
	local Destination = GetRandomNotVisitedCell(self)
	SetCellToVisited(self, Destination)

	while self.NonVisitedCells[1] do
		local NeighbourCell
		local CurrentCell = GetRandomNotVisitedCell(self)
		if not CurrentCell then break end

		local walk = { CurrentCell }

		repeat
			CurrentCell = walk[#walk]
			local RandomDirection = RandomPossibleDirection(self, CurrentCell, walk)
			local NeighbourCell = GetCellFromDirection(self, CurrentCell, RandomDirection)

			if not table.find(walk, NeighbourCell) then
				walk[#walk + 1] = NeighbourCell
				ChangeCellFloorColor(self, NeighbourCell, Color3.new(0, 1, 0))
			elseif table.find(walk, NeighbourCell) then
				walk = EraseLoop(self, NeighbourCell, walk)
			end

			CurrentIteration += 1
		until self.Cells[NeighbourCell].Visited

		for i, Cell in walk do
			SetCellToVisited(self, Cell)
			ChangeCellFloorColor(self, Cell, Color3.new(0, 0, 1))
			if not walk[i+1] then continue end

			self.Cells[Cell].Direction = GetDirectionBetweenCells(self, Cell, walk[i+1])
			self.Cells[walk[i+1]].Direction = GetDirectionBetweenCells(self, walk[i+1], Cell)
		end

		if CurrentIteration % UpdateInterval == 0 then
			UpdateMazeWithCells(self, self.Cells)
			task.wait()
		end
	end

	for Coord, Info in self.Cells do
		self.MazeFolder:FindFirstChild(Coord).Middle.Transparency = 0
		ChangeCellFloorColor(self, Coord, Color3.new(0, 0, 1))
	end

end

function MazeGenerator.BinaryTree(self : Maze)
	local Cells = {} :: {string : Cell}
	local RandomDirection = {"S", "W"}

	for x = 0, self.GridSize do
		for z = 0, self.GridSize do
			local Dir = RandomDirection[math.random(1, 2)]
			if x == 0 then Dir = "S" end
			if z == 10 then Dir = "W" end
			if x == 0 and z == 10 then Dir = "I" end
			Cells[x..","..z] = {Direction = Dir, Visited = true}
		end
	end

	self.Cells = Cells

	UpdateMazeWithCells(self, Cells)
end

function MazeGenerator.Prism(self : Maze)
	local Cells = {} :: {string : Cell}
	local NonVisitedCells = {} :: {string}
	local VisitedCells = {} :: {string}

	for x = 0, self.GridSize do
		for z = 0, self.GridSize do
			Cells[x..","..z] = {Direction = "I", Visited = false}
			table.insert(NonVisitedCells, x..","..z)
		end
	end

	self.Cells = Cells
	self.NonVisitedCells = NonVisitedCells

	local CurrentIteration = 0

	UpdateMazeWithCells(self, Cells)

	local CurrentCell = GetRandomNotVisitedCell(self)
	table.insert(VisitedCells, CurrentCell)
	self.MazeFolder:FindFirstChild(CurrentCell).Middle.Transparency = 1

	local FinishedCell = 0

	while self.NonVisitedCells[1] or FinishedCell >= self.GridSize ^ 2 do
		if #VisitedCells < 1 then break end
		local RandomVisitedCell = VisitedCells[math.random(1, #VisitedCells)]
		local RandomNotVisitedDir = RandomPossibleNotVisitedDirection(self, RandomVisitedCell)

		if not RandomNotVisitedDir then 
			self.Cells[RandomVisitedCell].Visited = true

			ChangeCellFloorColor(self, RandomVisitedCell, Color3.new(0, 0, 1))
			self.MazeFolder:FindFirstChild(RandomVisitedCell).Middle.Transparency = 0

			table.remove(VisitedCells, table.find(VisitedCells, RandomVisitedCell))
			FinishedCell += 1
			continue
		end

		self.Cells[RandomVisitedCell].Direction = RandomNotVisitedDir

		local NeighbourCell = GetCellFromDirection(self, RandomVisitedCell, RandomNotVisitedDir)
		if not NeighbourCell then print(RandomVisitedCell, RandomNotVisitedDir) end

		self.MazeFolder:FindFirstChild(NeighbourCell).Middle.Transparency = 0
		ChangeCellFloorColor(self, NeighbourCell, Color3.new(0, 1, 0))

		table.insert(VisitedCells, NeighbourCell)
		table.remove(NonVisitedCells, table.find(NonVisitedCells, NeighbourCell))

		UpdateMazeWithCells(self, self.Cells)
		task.wait()
	end
	UpdateMazeWithCells(self, self.Cells)
end

local function CalculateHcost(self : Maze, Start : string, Goal : string)
	local D = 10
	local Distance = (self.MazeFolder:FindFirstChild(Start):GetPivot().Position - self.MazeFolder:FindFirstChild(Goal):GetPivot().Position).Magnitude
	local HeuristicDistance = Distance * D
	return HeuristicDistance
end

local function IsTraversable(self : Maze, Cell : string, Destination : string, Direction : string) : boolean
	local CellDir = self.Cells[Cell].Direction
	local CellModel = self.MazeFolder:FindFirstChild(Cell)
	local DestinationDir = self.Cells[Destination].Direction
	local DestinationModel = self.MazeFolder:FindFirstChild(Destination)

	if CellDir == AbbreviateDir(Direction) then return true end
	if OppositeDirection(DestinationDir) == AbbreviateDir(Direction) then return true end
	if CellModel[Direction].Transparency == 1 and DestinationModel[UnAbbreviateDir(OppositeDirection(AbbreviateDir(Direction)))].Transparency == 1 then return true end 

	return
end

local function GetPath(self : Maze, CellInfo : {[string] : AStarCellInfo}, Cell : string) 
	local Distance = 80
	local Current : AStarCellInfo = CellInfo[Cell]
	local Path = {}
	local TotalDistance = 0
	while Current.Origin do
		TotalDistance += Distance
		if table.find(Path, Current.Origin) then break end
		table.insert(Path, Current.Origin)
		Current = CellInfo[Current.Origin]
	end

	return {Path = Path, Distance = TotalDistance}
end

local function CalculateGcost(self : Maze, CellInfo : {[string] : AStarCellInfo}, Cell : string)
	return GetPath(self, CellInfo, Cell).Distance
end

local function CalculateFcost(self : Maze, CellInfo : {[string] : AStarCellInfo}, Cell : string, Goal : string)
	local Gcost = CalculateGcost(self, CellInfo, Cell)
	local Hcost = CalculateHcost(self, Cell, Goal)
	--print(Gcost, Hcost)
	return Gcost + Hcost
end

local function GetLowestFcost(self : Maze, CellInfo : {[string] : AStarCellInfo})
	local LowestNumber = nil
	local CurrentLowest = {}

	for Coord, Info in CellInfo do
		if not Info.Fcost then continue end
		if Info.Closed then continue end

		if not LowestNumber then 
			LowestNumber = Info.Fcost 
			CurrentLowest = { Coord }  
			continue 
		end

		if Info.Fcost < LowestNumber then 
			CurrentLowest = { Coord } 
		elseif Info.Fcost == LowestNumber then
			table.insert(CurrentLowest, Coord)
		end
	end

	local LowestHcost = CellInfo[CurrentLowest[1]].Hcost
	local LowestCoord = CurrentLowest[1]

	for _, Coord in CurrentLowest do
		if CellInfo[Coord].Hcost < LowestHcost then LowestCoord = Coord end
	end

	return LowestCoord
end

local function UpdatePathWithCells(self : Maze, CellInfo : {[string] : AStarCellInfo})
	local MazeFolder = self.MazeFolder

	for Coord, Cell in CellInfo do
		self.MazeFolder:FindFirstChild(Coord).Middle.Transparency = 0
		if Cell.Start then ChangeCellFloorColor(self, Coord, Color3.new(1,1,1)) continue end
		if Cell.Goal then ChangeCellFloorColor(self, Coord, Color3.new(0)) continue end
		if Cell.Closed then ChangeCellFloorColor(self, Coord, Color3.new(1, 0, 0)) continue end

		ChangeCellFloorColor(self, Coord, Color3.new(0, 1, 0))
	end
end

function MazeGenerator.SolveWithAStar(self : Maze, Start : string, Goal : string, UpdateInterval : number?)
	local Cells = {} :: {string : Cell}
	local CellInfo = {} :: {[string] : AStarCellInfo}

	local Iter = 0
	for Cell, Info in self.Cells do
		CellInfo[Cell] = {Closed = false, PathDistance = 565}
	end


	CellInfo[Start] = {Fcost = CalculateHcost(self, Start, Goal), Hcost = CalculateHcost(self, Start, Goal), Gcost = CalculateGcost(self, CellInfo, Start), Closed = false, Start = true}
	CellInfo[Goal] = {Closed = false, PathDistance = 565, Goal = true}
	local Current = Start
	if not UpdateInterval then UpdateInterval = 1 end

	while Current ~= Goal do
		Current = GetLowestFcost(self, CellInfo)
		CellInfo[Current].Closed = true
		local NeighbourCells = GetNeighbourCoords(self, Current)

		for Direction, Coord in NeighbourCells do		
			if not IsTraversable(self, Current, Coord, Direction) or CellInfo[Coord].Closed then continue end
			if CellInfo[Coord].Start then continue end

			if GetPath(self, CellInfo, Coord).Distance < CellInfo[Coord].PathDistance or not CellInfo[Coord].Closed then 
				CellInfo[Coord].Fcost = CalculateFcost(self, CellInfo, Coord, Goal)
				CellInfo[Coord].Gcost = CalculateGcost(self, CellInfo, Coord)
				CellInfo[Coord].Hcost = CalculateHcost(self, Coord, Goal)
				CellInfo[Coord].Origin = Current
				if CellInfo[Coord].Closed then CellInfo[Coord].Closed = false end
			end

			Iter += 1
			if Iter % UpdateInterval == 0 then
				UpdatePathWithCells(self, CellInfo)
				task.wait()
			end
		end
	end

	UpdatePathWithCells(self, CellInfo)

	for _, Coord in GetPath(self, CellInfo, Current).Path do
		ChangeCellFloorColor(self, Coord, Color3.new(0, 0, 1))
	end
	ChangeCellFloorColor(self, Start, Color3.new(1, 1, 1))
	ChangeCellFloorColor(self, Goal, Color3.new(0, 0, 0))

end

return MazeGenerator
