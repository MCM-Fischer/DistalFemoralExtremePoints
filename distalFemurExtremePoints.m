function EP = distalFemurExtremePoints(distalFemurUSP, side, PFEA, varargin)
% TODO
% 
% INPUT:
%   - REQUIRED:
%     TODO
% 
%   - OPTIONAL:
%     TODO
% 
% OUTPUT:
%     TODO
% 
% EXAMPLE:
%     Run the file 'DistalFemurExtremePoints_Example.m'
% 
% TODO:
%   - Parsing
%   - Revise documentation
% 
% AUTHOR: Maximilian C. M. Fischer
% 	mediTEC - Chair of Medical Engineering, RWTH Aachen University
% VERSION: 1.0.1
% DATE: 2018-08-14
% LICENSE: Modified BSD License (BSD license with non-military-use clause)

addpath(genpath([fileparts([mfilename('fullpath'), '.m']) '\src']));

%% Parse inputs
p = inputParser;
logParValidFunc=@(x) (islogical(x) || isequal(x,1) || isequal(x,0));
addRequired(p,'distalFemurUSP',@(x) isstruct(x) && isfield(x, 'vertices') && isfield(x,'faces'))
addRequired(p,'side',@(x) any(validatestring(upper(x(1)),{'R','L'})));
addParameter(p,'visualization',false,logParValidFunc);
addParameter(p,'debugVisualization',false,logParValidFunc);
parse(p, distalFemurUSP, side, varargin{:});
side = upper(p.Results.side(1));
visu = logical(p.Results.visualization);
debugVisu = logical(p.Results.debugVisualization);

%% Settings
% Sigma: For explanation see the function: BOMultiScaleCurvature2D_adapted.m
sigmaStart = 1;
sigmaDelta = 1;
sigmaMedial = 4;
sigmaIntercondylar = 6;
sigmaLateral = 4;

%% Find boundary points of the condyles
% Intersection points between the mesh an the posterior foci elliptical axis 
PFEA_IS_Pts = intersectLineMesh3d(PFEA, distalFemurUSP.vertices, distalFemurUSP.faces);

% Should be always 4 points
if size(PFEA_IS_Pts,1) ~= 4
    error('PFEA intersection points with the distal femur mesh ~= 4')
end

% The intersection points devide the distal femur into 3 parts in Z direction:
% Negative Z = NZ
% Middle     = MZ
% Positive Z = PZ
switch side
    case 'R'
        % RIGHT knee: medial - neg. Z values (NZ), lateral - pos. Z values (PZ)
        SC(1).Zone = 'NZ';
        SC(2).Zone = 'MZ';
        SC(3).Zone = 'PZ';
    case 'L'
        %  LEFT knee: medial - pos. Z values (PZ), lateral - neg. Z values (NZ)
        SC(1).Zone = 'PZ';
        SC(2).Zone = 'MZ';
        SC(3).Zone = 'NZ';
end

% Assign them to the zones
PISP{1,2} = ismember(PFEA_IS_Pts(:,3), min(PFEA_IS_Pts((PFEA_IS_Pts(:,3) < 0),3)));
PISP{2,2} = ismember(PFEA_IS_Pts(:,3), max(PFEA_IS_Pts((PFEA_IS_Pts(:,3) < 0),3)));
PISP{3,2} = ismember(PFEA_IS_Pts(:,3), min(PFEA_IS_Pts((PFEA_IS_Pts(:,3) > 0),3)));
PISP{4,2} = ismember(PFEA_IS_Pts(:,3), max(PFEA_IS_Pts((PFEA_IS_Pts(:,3) > 0),3)));

for i=1:size(PFEA_IS_Pts,1)
    PISP{i,3} = PFEA_IS_Pts(PISP{i,2},:);
end

% Start and end point of the zones, rounded to an integer value in Z direction
BORD_COL = 6; BORD_INT = 4;
NZS = PISP{1,3}; NZS(3) = ceil(NZS(3))+BORD_COL;
MZS = PISP{2,3}; MZS(3) = ceil(MZS(3));
PZS = PISP{3,3}; PZS(3) = ceil(PZS(3));
NZE = PISP{2,3}; NZE(3) = floor(NZE(3));
MZE = PISP{3,3}; MZE(3) = floor(MZE(3));
PZE = PISP{4,3}; PZE(3) = floor(PZE(3))-BORD_COL;

% The number of sagittal cuts per zone
SC(1).NoC = abs(NZS(3)-NZE(3))+1;
SC(2).NoC = abs(MZS(3)-MZE(3))+1;
SC(3).NoC = abs(PZS(3)-PZE(3))+1;

SC(1).Origin = NZS;
SC(2).Origin = MZS;
SC(3).Origin = PZS;

LS = size(SC,2);
ZoneColors = parula(LS*2);

%% Sagittal Cuts (SC)
ZVector = [0, 0, 1];

Contours = cell(1,LS);
for s=1:LS
    SC(s).Color = ZoneColors(s,:);
    % Create cutting plane origins
    SC(s).PlaneOrigins = repmat(SC(s).Origin, SC(s).NoC, 1) + ...
        [zeros(SC(s).NoC,2), (0:SC(s).NoC-1)'];
    % Create SC(s).NoC Saggital Contour Profiles (SC(s).P)
    Contours{s} = IntersectMeshPlaneParfor(distalFemurUSP, SC(s).PlaneOrigins, ZVector);
    for c=1:SC(s).NoC
        % If there is more than one closed contour after the cut, use the longest one
        [~, IobC] = max(cellfun(@length, Contours{s}{c}));
        SC(s).P(c).xyz = Contours{s}{c}{IobC}';
        % Close contour: Copy start value to the end
        if ~isequal(SC(s).P(c).xyz(1,:),SC(s).P(c).xyz(end,:))
            SC(s).P(c).xyz(end+1,:) = SC(s).P(c).xyz(1,:);
        end
        % If the contour is sorted clockwise
        if sign(varea(SC(s).P(c).xyz')) == -1
            % Sort the contour counter-clockwise
            SC(s).P(c).xyz = flipud(SC(s).P(c).xyz);
        end
        % Set Start of the contour to the maximum Y value
        [~, IYMax] = max(SC(s).P(c).xyz(:,2));
        if IYMax ~= 1
            SC(s).P(c).xyz = SC(s).P(c).xyz([IYMax:length(SC(s).P(c).xyz),1:IYMax-1],:);
        end
    end
end

%% sagittalExPts = Sagittal Extreme Points
% A pattern-recognition algorithm for identifying the articulating surface
for s=1:LS
    for c=1:SC(s).NoC
        % Only the X & Y values are needed because the countours are parallel to the X-Y plane.
        Contour = SC(s).P(c).xyz(:,1:2);
        % Get the anterior and posterior extreme points of the articulating surface
        switch SC(s).Zone
            case 'NZ'
                [SC(s).P(c).A, SC(s).P(c).B, SC(s).P(c).H] = ...
                    sagittalExPts_MedCond(Contour, sigmaStart, sigmaDelta, sigmaMedial, debugVisu);
            case 'MZ'
                [SC(s).P(c).A, SC(s).P(c).B, SC(s).P(c).H] = ...
                    sagittalExPts_IntCond(Contour, sigmaStart, sigmaDelta, sigmaIntercondylar, debugVisu);
            case 'PZ'
                [SC(s).P(c).A, SC(s).P(c).B, SC(s).P(c).H] = ...
                    sagittalExPts_LatCond(Contour, sigmaStart, sigmaDelta, sigmaLateral, debugVisu);
        end
    end
end


%% Find global extreme points of the sagittal contours (SCs)
NZ = strcmp({SC(:).Zone}, 'NZ');
MZ = strcmp({SC(:).Zone}, 'MZ');
PZ = strcmp({SC(:).Zone}, 'PZ');

% Exclude border of the zones
SC(MZ).ExRange = BORD_INT:SC(MZ).NoC-BORD_INT;
switch side
    case 'R'
        SC(NZ).ExRange = 1:SC(NZ).NoC-BORD_INT;
        SC(PZ).ExRange = BORD_INT:SC(PZ).NoC;
    case 'L'
        SC(NZ).ExRange = BORD_INT:SC(NZ).NoC;
        SC(PZ).ExRange = 1:SC(PZ).NoC-BORD_INT;
end
% Take start points (A) of zone MZ specified by ExRange
Distal_MZ = nan(SC(MZ).NoC,3);
for c = SC(MZ).ExRange
    Distal_MZ(c,:) = SC(MZ).P(c).xyz(SC(MZ).P(c).A,:);
end
Distal_MZ(any(isnan(Distal_MZ),2),:)=[];
% Median of the start points
[~, ICN_Idx] = pdist2(distalFemurUSP.vertices,median(Distal_MZ),'euclidean','Smallest',1);
EP.Intercondylar = distalFemurUSP.vertices(ICN_Idx,:);

% Take start points (A) of zone NZ specified by ExRange
ProximalPosterior_NZ = nan(SC(NZ).NoC,3);
for c = SC(NZ).ExRange
    ProximalPosterior_NZ(c,:) = SC(NZ).P(c).xyz(SC(NZ).P(c).A,:);
end
ProximalPosterior_NZ(any(isnan(ProximalPosterior_NZ),2),:)=[];
% Median of the start points
[~, PPNZ_Idx] = pdist2(distalFemurUSP.vertices,median(ProximalPosterior_NZ),'euclidean','Smallest',1);
EP.Medial = distalFemurUSP.vertices(PPNZ_Idx,:);

% Take start points (A) of zone PZ specified by ExRange
ProximalPosterior_PZ = nan(SC(PZ).NoC,3);
for c = SC(PZ).ExRange
    ProximalPosterior_PZ(c,:) = SC(PZ).P(c).xyz(SC(PZ).P(c).A,:);
end
ProximalPosterior_PZ(any(isnan(ProximalPosterior_PZ),2),:)=[];
% Median of the start points
[~, PPPZ_Idx] = pdist2(distalFemurUSP.vertices,median(ProximalPosterior_PZ),'euclidean','Smallest',1);
EP.Lateral = distalFemurUSP.vertices(PPPZ_Idx,:);

% All end points (B) of the zones NZ, MZ, PZ
ProximalAnterior = nan(sum([SC.NoC]),3);
countIdx = 1;
for s=1:LS
    for c = 1:SC(s).NoC
        ProximalAnterior(countIdx,:) = SC(s).P(c).xyz(SC(s).P(c).B,:);
        countIdx = countIdx+1;
    end; clear c
end
% End point RC-MZ: Most proximal point of all end points (B) of the zones NZ, MZ, PZ
[~, I_ProximalAnterior_Ymax] = max(ProximalAnterior(:,2));
EP.Anterior = ProximalAnterior(I_ProximalAnterior_Ymax,:);

%% Visualization
if visu == 1
    [~, axH] = visualizeMeshes(distalFemurUSP);
    
    drawLine3d(axH, PFEA, 'b')
    
    for i=1:size(PFEA_IS_Pts,1)
        scatter3(axH, PISP{i,3}(1),PISP{i,3}(2),PISP{i,3}(3),'m','filled');
    end; clear i
    
    for s=1:LS
        for c=1:SC(s).NoC
            % Plot contour-part in 3D
            CP3D = SC(s).P(c).xyz;
            EPA = SC(s).P(c).A; EPB = SC(s).P(c).B;
            plot3(axH, CP3D(EPA:EPB,1),CP3D(EPA:EPB,2),CP3D(EPA:EPB,3),...
                'Color', 'k','Linewidth',1,'LineStyle','--');
        end
        for c=SC(s).ExRange
            % Plot contour-part in 3D
            CP3D = SC(s).P(c).xyz;
            EPA = SC(s).P(c).A; EPB = SC(s).P(c).B;
            plot3(axH, CP3D(EPA:EPB,1),CP3D(EPA:EPB,2),CP3D(EPA:EPB,3),...
                'Color', SC(s).Color,'Linewidth',2);
        end
    end
    
    T = EP.Medial;  scatter3(axH, T(1),T(2),T(3),'r','filled');
    text(axH, T(1),T(2),T(3), 'Medial')
    T = EP.Intercondylar; scatter3(axH, T(1),T(2),T(3),'r','filled');
    text(axH, T(1),T(2),T(3), 'Intercondylar')
    T = EP.Lateral;  scatter3(axH, T(1),T(2),T(3),'r','filled');
    text(axH, T(1),T(2),T(3), 'Lateral')
    T = EP.Anterior;  scatter3(axH, T(1),T(2),T(3),'r','filled');
    text(axH, T(1),T(2),T(3), 'Anterior')
    
    anatomicalViewButtons(axH, 'ASR')
end

end